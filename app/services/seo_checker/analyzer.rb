# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"

module SeoChecker
  # 単一 HTML からヒューリスティック採点する。
  # クラスター性はパンくず / URL ジャンル階層 / 内部リンクから推定する。
  class Analyzer
    Result = Struct.new(
      :url,
      :final_url,
      :title,
      :overall_score,
      :axes,
      :cluster,
      :improvements,
      :stats,
      keyword_init: true
    )

    AXIS_WEIGHTS = {
      content: 0.30,
      basic_seo: 0.25,
      specificity: 0.20,
      cluster: 0.25
    }.freeze

    NOISE_SELECTORS = [
      "script", "style", "noscript", "svg", "iframe",
      "nav", "footer", "header", "aside",
      ".nav", ".navbar", ".footer", ".header", ".sidebar", ".menu", ".cookie",
      ".breadcrumb", ".breadcrumbs", ".pankuzu",
      "[class*='-nav']", "[class*='nav-']", "[class*='-footer']", "[class*='footer-']",
      "[class*='cookie']"
    ].join(", ").freeze

    CARD_ARTICLE_CLASS = /card|teaser|widget|tile|item|feature-card|feature-focus|slide|swiper/i.freeze

    class << self
      def analyze(url:, html:, final_url: nil)
        doc = Nokogiri::HTML(html.to_s)
        final = final_url.presence || url
        uri = URI.parse(final)

        stats = extract_stats(doc, uri)
        breadcrumbs = extract_breadcrumbs(doc)
        cluster_info = estimate_cluster(uri, breadcrumbs, stats)

        axes = {
          content: score_content(stats),
          basic_seo: score_basic_seo(stats),
          specificity: score_specificity(doc, stats),
          cluster: score_cluster(cluster_info)
        }

        overall = weighted_overall(axes)

        Result.new(
          url: url,
          final_url: final,
          title: stats[:title],
          overall_score: overall,
          axes: axes,
          cluster: cluster_info,
          improvements: build_improvements(axes, stats, cluster_info),
          stats: stats.merge(breadcrumb_labels: breadcrumbs)
        )
      end

      def weighted_overall(axes)
        parts = AXIS_WEIGHTS.filter_map do |key, weight|
          axis = axes[key]
          next if axis.nil? || axis[:excluded]
          next if axis[:score].nil?

          [axis[:score].to_f, weight]
        end
        return 0 if parts.empty?

        total_weight = parts.sum { |(_, w)| w }
        (parts.sum { |(score, w)| score * w } / total_weight).round
      end

      private

      def extract_stats(doc, uri)
        title = doc.at_css("title")&.text.to_s.gsub(/\s+/, " ").strip
        meta_desc = meta_content(doc, "description")
        h1s = doc.css("h1").map { |n| clean_text(n.text) }.reject(&:blank?)

        content_root = content_root_node(doc)
        content_clone = content_root.dup
        content_clone.css(NOISE_SELECTORS).remove
        body_text = clean_text(content_clone.text)
        char_count = body_text.gsub(/\s+/, "").length

        heading_scope = content_clone
        h2_count = heading_scope.css("h2").size
        h3_count = heading_scope.css("h3").size
        # 見出しが content 外だけにある場合のフォールバック
        if h2_count.zero?
          h2_count = doc.css("h2").size
          h3_count = doc.css("h3").size
        end

        images = content_clone.css("img")
        images = doc.css("img") if images.empty?
        images_with_alt = images.count { |img| img["alt"].to_s.strip.present? }

        same_host_links = extract_internal_links(doc, uri)

        {
          title: title,
          title_length: title.length,
          meta_description: meta_desc,
          meta_description_length: meta_desc.length,
          h1_count: h1s.size,
          h1_text: h1s.first.to_s,
          h2_count: h2_count,
          h3_count: h3_count,
          char_count: char_count,
          paragraph_count: content_clone.css("p").count { |p| clean_text(p.text).length > 40 },
          list_count: content_clone.css("ul, ol").size,
          table_count: content_clone.css("table").size,
          image_count: images.size,
          images_with_alt: images_with_alt,
          has_canonical: doc.at_css('link[rel="canonical"]').present?,
          has_og_title: meta_property(doc, "og:title").present?,
          has_viewport: doc.at_css('meta[name="viewport"]').present?,
          has_json_ld: doc.css('script[type="application/ld+json"]').any?,
          path_segments: uri.path.to_s.split("/").reject(&:blank?),
          page_url: uri.to_s,
          page_path: normalize_path(uri.path),
          is_top_page: top_page?(uri),
          internal_link_count: same_host_links.size,
          internal_links: same_host_links.first(80),
          body_text_sample: body_text[0, 5_000]
        }
      end

      def top_page?(uri)
        path = uri.path.to_s
        path.blank? || path == "/"
      end

      # 最初の <article> はカード部品であることが多いので、
      # ノイズ除去後の文字量が最大の候補を本文ルートにする。
      def content_root_node(doc)
        candidates = []
        candidates << doc.at_css('[role="main"]')
        candidates << doc.at_css("main")

        doc.css("article").each do |node|
          next if node["class"].to_s.match?(CARD_ARTICLE_CLASS)
          next if visible_text_length(node) < 200

          candidates << node
        end

        %w[
          .post-content .entry-content .article-body .content #content .post .entry
          .meetia-modern-lp .drafify-lp [class*="modern-lp"] [class*="-lp-body"] [class*="lp-body"]
        ].each do |sel|
          candidates.concat(doc.css(sel).to_a)
        end

        candidates << doc.at_css("body")
        candidates = candidates.compact.uniq

        best = candidates.max_by { |node| visible_text_length(node) }
        best || doc.at_css("body")
      end

      def visible_text_length(node)
        return 0 unless node

        clone = node.dup
        clone.css(NOISE_SELECTORS).remove
        clone.text.to_s.gsub(/\s+/, "").length
      rescue StandardError
        0
      end

      def extract_internal_links(doc, uri)
        doc.css("a[href]").filter_map do |a|
          href = a["href"].to_s.strip
          next if href.blank? || href.start_with?("#", "mailto:", "tel:", "javascript:")

          begin
            link_uri = uri.merge(href)
            next unless link_uri.host.to_s.downcase == uri.host.to_s.downcase

            {
              href: normalize_path(link_uri.path),
              text: clean_text(a.text)
            }
          rescue StandardError
            nil
          end
        end.uniq { |l| [l[:href], l[:text]] }
      end

      def clean_text(text)
        text.to_s.gsub(/\s+/, " ").strip
      end

      def meta_content(doc, name)
        node = doc.at_css("meta[name='#{name}']") || doc.at_css("meta[name='#{name.downcase}']")
        node ||= doc.at_css("meta[property='og:description']") if name == "description"
        node&.[]("content").to_s.strip
      end

      def meta_property(doc, property)
        doc.at_css("meta[property='#{property}']")&.[]("content").to_s.strip
      end

      def extract_breadcrumbs(doc)
        candidates = [
          breadcrumbs_from_jsonld(doc),
          breadcrumbs_from_microdata(doc),
          breadcrumbs_from_nav(doc)
        ]
        candidates.max_by(&:size)
      end

      def typed_as?(data, type_name)
        Array.wrap(data["@type"]).map(&:to_s).any? { |t| t.include?(type_name) }
      end

      def breadcrumbs_from_jsonld(doc)
        best = []
        doc.css('script[type="application/ld+json"]').each do |node|
          raw = node.text.to_s
          next if raw.blank?

          data = JSON.parse(raw) rescue next
          items = Array.wrap(data).flat_map { |d| flatten_jsonld(d) }
          breadcrumb = items.find { |d| d.is_a?(Hash) && typed_as?(d, "BreadcrumbList") }
          next unless breadcrumb

          elements = Array.wrap(breadcrumb["itemListElement"]).sort_by { |el| el.is_a?(Hash) ? el["position"].to_i : 0 }
          labels = elements.filter_map { |el| breadcrumb_item_name(el) }
          best = labels if labels.size > best.size
        end
        best
      end

      def breadcrumb_item_name(el)
        return nil unless el.is_a?(Hash)

        name = el["name"].presence
        item = el["item"]
        if item.is_a?(Hash)
          name ||= item["name"].presence
        end
        clean_text(name).presence
      end

      def flatten_jsonld(data)
        case data
        when Array then data.flat_map { |d| flatten_jsonld(d) }
        when Hash
          graph = data["@graph"]
          graph ? flatten_jsonld(graph) + [data] : [data]
        else
          []
        end
      end

      def breadcrumbs_from_microdata(doc)
        root = doc.at_css('[itemtype*="BreadcrumbList"]')
        return [] unless root

        labels = root.css('[itemprop="name"]').map { |n| clean_text(n.text) }.reject(&:blank?)
        return labels if labels.size >= 2

        root.css('[itemprop="itemListElement"]').filter_map do |el|
          clean_text(el.at_css('[itemprop="name"]')&.text || el.text).presence
        end.uniq
      end

      def breadcrumbs_from_nav(doc)
        selectors = [
          "nav.breadcrumb", ".breadcrumb", ".breadcrumbs", "ol.breadcrumb", "ul.breadcrumb",
          ".pankuzu", ".pan", "#breadcrumb", "#breadcrumbs", ".topic-path", ".topicpath"
        ]

        nav = nil
        selectors.each do |sel|
          nav = doc.at_css(sel)
          break if nav
        end

        unless nav
          nav = doc.css("[class], [id], nav, [aria-label]").find do |node|
            label = "#{node['aria-label']} #{node['class']} #{node['id']}".downcase
            label.match?(/breadcrumb|パンくず|pankuzu|topic.?path/)
          end
        end
        return [] unless nav

        texts = nav.css("a, [itemprop='name'], li > span, li > strong").map { |n| clean_text(n.text) }
        texts = nav.css("a, li, span").map { |n| clean_text(n.text) } if texts.size < 2
        texts.reject(&:blank?).reject { |t| t.match?(/\A[>\/›»\|]+\z/) }.uniq
      end

      def estimate_cluster(uri, breadcrumbs, stats)
        segments = stats[:path_segments]
        crumbs = breadcrumbs.dup

        # ホーム相当を除いた階層
        topical_crumbs = crumbs.reject { |c| c.match?(/\A(ホーム|home|top|トップ)\z/i) }

        pillar_candidate = nil
        cluster_candidate = nil
        genre_hint = nil

        if topical_crumbs.size >= 3
          genre_hint = topical_crumbs[0]
          pillar_candidate = topical_crumbs[-2]
          cluster_candidate = topical_crumbs[-1]
        elsif topical_crumbs.size == 2
          genre_hint = topical_crumbs[0]
          pillar_candidate = topical_crumbs[0]
          cluster_candidate = topical_crumbs[-1]
        elsif topical_crumbs.size == 1
          cluster_candidate = topical_crumbs[0]
        end

        # URL パスからの補完（例: /seo/pillar/cluster, /ai_article/columns/slug）
        if segments.size >= 2
          genre_hint ||= humanize_segment(segments[0])
          if pillar_candidate.blank?
            if segments.size >= 3
              pillar_candidate = humanize_segment(segments[-2])
              cluster_candidate ||= humanize_segment(segments[-1])
            elsif segments.size == 2
              # /genre/article → ジャンルをピラー候補、記事をクラスター候補
              pillar_candidate = humanize_segment(segments[0])
              cluster_candidate ||= humanize_segment(segments[-1])
            end
          else
            cluster_candidate ||= humanize_segment(segments[-1]) if segments.any?
          end
        elsif segments.size == 1
          cluster_candidate ||= humanize_segment(segments[0])
        end

        # H1 をクラスター候補の補強に（トップページは除外）
        if !stats[:is_top_page] && cluster_candidate.blank? && stats[:h1_text].present?
          cluster_candidate = stats[:h1_text]
        end

        parent_paths = candidate_parent_paths(segments)
        links_to_parent = parent_paths.any? do |parent|
          stats[:internal_links].any? { |l| l[:href] == parent }
        end

        # パンくず名と一致する内部リンクも親リンク扱い
        parent_labels = [pillar_candidate, genre_hint].compact
        links_to_parent ||= stats[:internal_links].any? do |l|
          parent_labels.any? { |label| label.present? && l[:text].include?(label) }
        end

        sibling_links = count_sibling_links(stats, segments, uri)

        detected = pillar_candidate.present? && cluster_candidate.present? &&
                   (topical_crumbs.size >= 2 || segments.size >= 2)

        evidence = []
        evidence << t_seo("evidence_crumbs", count: crumbs.size) if crumbs.size >= 2
        evidence << t_seo("evidence_path", count: segments.size) if segments.size >= 2
        evidence << t_seo("evidence_parent_link") if links_to_parent
        evidence << t_seo("evidence_siblings", count: sibling_links) if sibling_links.positive?
        evidence << t_seo("evidence_genre", genre: genre_hint) if genre_hint.present?
        if detected
          evidence << t_seo("evidence_estimate", pillar: pillar_candidate, cluster: truncate(cluster_candidate, 40))
        elsif stats[:is_top_page]
          evidence << t_seo("evidence_top")
        elsif evidence.empty?
          evidence << t_seo("evidence_none")
        end

        confidence = cluster_confidence(
          breadcrumb_depth: crumbs.size,
          topical_depth: topical_crumbs.size,
          path_depth: segments.size,
          links_to_parent: links_to_parent,
          sibling_links: sibling_links,
          detected: detected,
          top_page: stats[:is_top_page]
        )
        status = cluster_status(detected, confidence, crumbs, segments, top_page: stats[:is_top_page])

        {
          detected: detected,
          status: status,
          pillar_candidate: pillar_candidate,
          cluster_candidate: cluster_candidate,
          genre_hint: genre_hint,
          depth: [crumbs.size, segments.size].max,
          links_to_parent: links_to_parent,
          sibling_link_count: sibling_links,
          evidence: evidence,
          confidence: confidence
        }
      end

      def candidate_parent_paths(segments)
        return [] if segments.size < 2

        paths = []
        # 直上
        paths << normalize_path("/#{segments[0..-2].join('/')}")
        # さらに上（ジャンル直下）
        paths << normalize_path("/#{segments[0]}") if segments.size >= 3
        # /x/columns/slug → /x/columns も親候補
        if segments.size >= 3 && segments[-2].match?(/\A(columns|posts|articles|blog|category|categories)\z/i)
          paths << normalize_path("/#{segments[0..-2].join('/')}")
        end
        paths.uniq
      end

      def count_sibling_links(stats, segments, uri)
        return 0 if segments.size < 2

        parent = normalize_path("/#{segments[0..-2].join('/')}")
        current = normalize_path(uri.path)
        stats[:internal_links].count do |l|
          path = l[:href]
          path != current && path.start_with?("#{parent}/") && path.count("/") == parent.count("/") + 1
        end
      end

      def cluster_status(detected, confidence, crumbs, segments, top_page: false)
        return "not_applicable" if top_page && !detected && crumbs.size < 2
        return "detected" if detected && confidence.to_i >= 55
        return "weak" if detected || crumbs.size >= 2 || segments.size >= 2

        "undetected"
      end

      def cluster_confidence(breadcrumb_depth:, topical_depth:, path_depth:, links_to_parent:, sibling_links:, detected:, top_page: false)
        # トップはクラスター採点そのものを除外する（点数を付けない）
        return nil if top_page && !detected && breadcrumb_depth < 2

        score = 18
        score += 28 if topical_depth >= 3
        score += 18 if topical_depth == 2
        score += 10 if breadcrumb_depth >= 2
        score += 18 if path_depth >= 3
        score += 12 if path_depth == 2
        score += 16 if links_to_parent
        score += 12 if sibling_links >= 2
        score += 6 if sibling_links == 1
        score += 8 if detected
        [score, 100].min
      end

      def truncate(text, len)
        t = text.to_s
        t.length > len ? "#{t[0, len]}…" : t
      end

      def humanize_segment(segment)
        CGI.unescape(segment.to_s).tr("-_", " ").squeeze(" ").strip
      rescue StandardError
        segment.to_s
      end

      def normalize_path(path)
        p = path.to_s
        p = CGI.unescape(p) rescue p
        p = p.split("?").first.to_s
        p = p.chomp("/")
        p = "/#{p}" unless p.start_with?("/")
        p == "" ? "/" : p
      end

      def score_content(stats)
        score = 0
        notes = []
        chars = stats[:char_count]

        case chars
        when 2_500.. then score += 50; notes << t_seo("note_content_enough", chars: chars)
        when 1_500...2_500 then score += 42; notes << t_seo("note_content_ok", chars: chars)
        when 900...1_500 then score += 32; notes << t_seo("note_content_low", chars: chars)
        when 400...900 then score += 18; notes << t_seo("note_content_short", chars: chars)
        else score += 6; notes << t_seo("note_content_poor", chars: chars)
        end

        h2 = stats[:h2_count]
        case h2
        when 4..12 then score += 28; notes << t_seo("note_h2_good", count: h2)
        when 2..3 then score += 20; notes << t_seo("note_h2_ok", count: h2)
        when 13..24
          if chars >= 2_000
            score += 24
            notes << t_seo("note_h2_long_page", count: h2)
          else
            score += 14
            notes << t_seo("note_h2_scattered")
          end
        when 1 then score += 10; notes << t_seo("note_h2_few")
        else score += 4; notes << t_seo("note_h2_weak")
        end

        score += 12 if stats[:h3_count].between?(1, 40)
        score += 10 if stats[:paragraph_count] >= 4
        score += 6 if stats[:table_count].to_i.positive?
        score = [score, 100].min

        { score: score, note: notes.first(2).join(" / ") }
      end

      def score_basic_seo(stats)
        score = 8
        notes = []
        desc_issue = false

        title_len = stats[:title_length]
        if title_len.between?(25, 70)
          score += 24
          notes << t_seo("note_title_good")
        elsif title_len.between?(12, 90)
          score += 14
          notes << t_seo("note_title_ok")
        elsif title_len.positive?
          score += 6
          notes << t_seo("note_title_bad")
        else
          notes << t_seo("note_title_missing")
        end

        desc_len = stats[:meta_description_length]
        if desc_len.between?(60, 180)
          score += 22
          notes << t_seo("note_desc_good", chars: desc_len)
        elsif desc_len.between?(40, 220)
          score += 12
          notes << t_seo("note_desc_ok", chars: desc_len)
        elsif desc_len.positive?
          score += 4
          desc_issue = true
          notes << t_seo("note_desc_short", chars: desc_len)
        else
          desc_issue = true
          notes << t_seo("note_desc_missing")
        end

        case stats[:h1_count]
        when 1 then score += 18
        when 2..3 then score += 10; notes << t_seo("note_h1_multi")
        else notes << t_seo("note_h1_bad")
        end

        score += 10 if stats[:has_canonical]
        score += 8 if stats[:has_og_title]
        score += 6 if stats[:has_viewport]
        score += 6 if stats[:has_json_ld]

        if stats[:image_count].positive?
          ratio = stats[:images_with_alt].to_f / stats[:image_count]
          score += (ratio * 8).round
          notes << t_seo("note_alt_weak") if ratio < 0.6
        else
          score += 4
        end

        score = [score, 100].min
        {
          score: score,
          note: notes.first(2).join(" / ").presence || t_seo("note_basic_fallback"),
          desc_issue: desc_issue
        }
      end

      def score_specificity(doc, stats)
        score = 28
        notes = []
        sample = stats[:body_text_sample].to_s

        number_hits = sample.scan(/(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?%?|円|万円|社|件|人|年|月|日/).size
        if number_hits >= 6
          score += 22
          notes << t_seo("note_spec_rich")
        elsif number_hits >= 2
          score += 14
          notes << t_seo("note_spec_ok")
        else
          notes << t_seo("note_spec_poor")
        end

        if stats[:list_count] >= 2
          score += 14
          notes << t_seo("note_lists")
        elsif stats[:list_count] == 1
          score += 8
        end

        page_host = begin
          URI.parse(stats[:page_url].to_s).host
        rescue StandardError
          nil
        end
        external_links = doc.css("a[href^='http']").count do |a|
          href = a["href"].to_s
          begin
            host = URI.parse(href).host
            host.present? && page_host.present? && host.downcase != page_host.downcase
          rescue StandardError
            false
          end
        end
        if external_links >= 1
          score += 10
          notes << t_seo("note_external")
        end

        author_or_date = doc.at_css('time, [itemprop="datePublished"], [itemprop="author"], [rel="author"], .author, .byline')
        score += 8 if author_or_date
        score += 8 if sample.match?(/例えば|具体的|手順|ステップ|ポイント|まとめ|比較|方法|やり方|how to|for example|step|summary/i)
        score += 10 if stats[:char_count] >= 1_500 && stats[:h2_count] >= 2

        score = [score, 100].min
        { score: score, note: notes.first(2).join(" / ").presence || t_seo("note_spec_fallback") }
      end

      def score_cluster(cluster_info)
        case cluster_info[:status]
        when "detected"
          {
            score: cluster_info[:confidence],
            excluded: false,
            note: t_seo("note_cluster_detected", pillar: cluster_info[:pillar_candidate])
          }
        when "weak"
          {
            score: cluster_info[:confidence],
            excluded: false,
            note: t_seo("note_cluster_weak", detail: cluster_info[:evidence].first)
          }
        when "not_applicable"
          {
            score: nil,
            excluded: true,
            note: t_seo("note_cluster_na")
          }
        else
          {
            score: cluster_info[:confidence],
            excluded: false,
            note: t_seo("note_cluster_undetected")
          }
        end
      end

      def build_improvements(axes, stats, cluster_info)
        tips = []

        tips << t_seo("tip_content", chars: stats[:char_count]) if axes[:content][:score] < 70
        tips << t_seo("tip_h2") if stats[:h2_count] < 3 && !stats[:is_top_page]
        if stats[:meta_description_length].zero?
          tips << t_seo("tip_desc_missing")
        elsif stats[:meta_description_length] < 60
          tips << t_seo("tip_desc_short", chars: stats[:meta_description_length])
        elsif stats[:meta_description_length] > 180
          tips << t_seo("tip_desc_long", chars: stats[:meta_description_length])
        end
        tips << t_seo("tip_h1") if stats[:h1_count] != 1
        tips << t_seo("tip_specificity") if axes[:specificity][:score] < 65
        if cluster_info[:status] == "undetected"
          tips << t_seo("tip_cluster_undetected")
        elsif cluster_info[:status] == "not_applicable"
          tips << t_seo("tip_cluster_na")
        elsif !cluster_info[:links_to_parent] && cluster_info[:pillar_candidate].present?
          tips << t_seo("tip_parent_link")
        end
        if axes[:basic_seo][:score] < 70 && !axes[:basic_seo][:desc_issue]
          tips << t_seo("tip_basic_tags")
        end

        tips.first(3)
      end

      def t_seo(key, **opts)
        I18n.t("drafity.seo_checker.#{key}", **opts)
      end
    end
  end
end
