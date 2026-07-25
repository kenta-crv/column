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
      content: 0.25,
      basic_seo: 0.25,
      specificity: 0.25,
      cluster: 0.25
    }.freeze

    class << self
      def analyze(url:, html:, final_url: nil)
        doc = Nokogiri::HTML(html.to_s)
        final = final_url.presence || url
        uri = URI.parse(final)

        stats = extract_stats(doc, uri)
        breadcrumbs = extract_breadcrumbs(doc)
        cluster_info = estimate_cluster(doc, uri, breadcrumbs, stats)

        axes = {
          content: score_content(stats),
          basic_seo: score_basic_seo(doc, stats),
          specificity: score_specificity(doc, stats),
          cluster: score_cluster(cluster_info, breadcrumbs)
        }

        overall = AXIS_WEIGHTS.sum { |key, weight| axes[key][:score] * weight }.round

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

      private

      def extract_stats(doc, uri)
        title = doc.at_css("title")&.text.to_s.gsub(/\s+/, " ").strip
        meta_desc = meta_content(doc, "description")
        h1s = doc.css("h1").map { |n| n.text.to_s.gsub(/\s+/, " ").strip }.reject(&:blank?)
        h2_count = doc.css("h2").size
        h3_count = doc.css("h3").size

        body_node = doc.at_css("article") || doc.at_css("main") || doc.at_css("body")
        body_text = body_node ? body_node.text.to_s.gsub(/\s+/, " ").strip : ""
        char_count = body_text.gsub(/\s+/, "").length

        images = doc.css("img")
        images_with_alt = images.count { |img| img["alt"].to_s.strip.present? }

        same_host_links = doc.css("a[href]").filter_map do |a|
          href = a["href"].to_s.strip
          next if href.blank? || href.start_with?("#", "mailto:", "tel:", "javascript:")

          begin
            link_uri = uri.merge(href)
            next unless link_uri.host == uri.host

            { href: link_uri.path.to_s, text: a.text.to_s.gsub(/\s+/, " ").strip }
          rescue StandardError
            nil
          end
        end.uniq { |l| l[:href] }

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
          paragraph_count: doc.css("p").count { |p| p.text.to_s.strip.length > 40 },
          list_count: doc.css("ul, ol").size,
          image_count: images.size,
          images_with_alt: images_with_alt,
          has_canonical: doc.at_css('link[rel="canonical"]').present?,
          has_og_title: meta_property(doc, "og:title").present?,
          has_viewport: doc.at_css('meta[name="viewport"]').present?,
          has_json_ld: doc.css('script[type="application/ld+json"]').any?,
          path_segments: uri.path.to_s.split("/").reject(&:blank?),
          page_url: uri.to_s,
          internal_link_count: same_host_links.size,
          internal_links: same_host_links.first(40),
          body_text_sample: body_text[0, 4_000]
        }
      end

      def meta_content(doc, name)
        doc.at_css("meta[name='#{name}']")&.[]("content").to_s.strip
      end

      def meta_property(doc, property)
        doc.at_css("meta[property='#{property}']")&.[]("content").to_s.strip
      end

      def extract_breadcrumbs(doc)
        from_jsonld = breadcrumbs_from_jsonld(doc)
        return from_jsonld if from_jsonld.size >= 2

        from_nav = breadcrumbs_from_nav(doc)
        return from_nav if from_nav.size >= 2

        from_jsonld.presence || from_nav
      end

      def breadcrumbs_from_jsonld(doc)
        labels = []
        doc.css('script[type="application/ld+json"]').each do |node|
          data = JSON.parse(node.text) rescue next
          items = Array.wrap(data).flat_map { |d| flatten_jsonld(d) }
          breadcrumb = items.find { |d| d.is_a?(Hash) && d["@type"].to_s.include?("BreadcrumbList") }
          next unless breadcrumb

          elements = Array.wrap(breadcrumb["itemListElement"]).sort_by { |el| el["position"].to_i }
          labels = elements.filter_map do |el|
            name = el.dig("item", "name") || el["name"]
            name.to_s.strip.presence
          end
          break if labels.size >= 2
        end
        labels
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

      def breadcrumbs_from_nav(doc)
        nav = doc.at_css('nav.breadcrumb, .breadcrumb, .breadcrumbs, ol.breadcrumb')
        unless nav
          nav = doc.css("nav, [aria-label]").find do |node|
            label = node["aria-label"].to_s.downcase
            label.include?("breadcrumb") || label.include?("パンくず")
          end
        end
        return [] unless nav

        nav.css("a, li, span").map { |n| n.text.to_s.gsub(/\s+/, " ").strip }.reject(&:blank?).uniq
      end

      def estimate_cluster(doc, uri, breadcrumbs, stats)
        segments = stats[:path_segments]
        depth = [breadcrumbs.size, segments.size].max

        pillar_candidate =
          if breadcrumbs.size >= 3
            breadcrumbs[-2]
          elsif breadcrumbs.size == 2
            breadcrumbs[-1]
          elsif segments.size >= 2
            humanize_segment(segments[-2])
          end

        cluster_candidate =
          if breadcrumbs.size >= 2
            breadcrumbs[-1]
          elsif segments.any?
            humanize_segment(segments[-1])
          end

        parent_path = segments.size >= 2 ? "/#{segments[0..-2].join('/')}" : nil
        links_to_parent = if parent_path
                            stats[:internal_links].any? { |l| normalize_path(l[:href]) == normalize_path(parent_path) }
                          else
                            false
                          end

        sibling_links = if parent_path
                          stats[:internal_links].count do |l|
                            path = normalize_path(l[:href])
                            path.start_with?("#{normalize_path(parent_path)}/") && path != normalize_path(uri.path)
                          end
                        else
                          0
                        end

        genre_hint = segments.first.presence || breadcrumbs[1]

        evidence = []
        evidence << "パンくず #{breadcrumbs.size} 階層" if breadcrumbs.size >= 2
        evidence << "URLパス #{segments.size} 階層" if segments.size >= 2
        evidence << "親パスへの内部リンクあり" if links_to_parent
        evidence << "同階層の関連リンク #{sibling_links} 件" if sibling_links.positive?
        evidence << "ジャンル候補: #{genre_hint}" if genre_hint.present?
        evidence << "階層シグナルが弱い" if evidence.empty?

        {
          pillar_candidate: pillar_candidate,
          cluster_candidate: cluster_candidate,
          genre_hint: genre_hint,
          depth: depth,
          links_to_parent: links_to_parent,
          sibling_link_count: sibling_links,
          evidence: evidence,
          confidence: cluster_confidence(breadcrumbs, segments, links_to_parent, sibling_links)
        }
      end

      def cluster_confidence(breadcrumbs, segments, links_to_parent, sibling_links)
        score = 0
        score += 35 if breadcrumbs.size >= 3
        score += 20 if breadcrumbs.size == 2
        score += 20 if segments.size >= 3
        score += 10 if segments.size == 2
        score += 20 if links_to_parent
        score += 15 if sibling_links >= 2
        score += 8 if sibling_links == 1
        [score, 100].min
      end

      def humanize_segment(segment)
        CGI.unescape(segment.to_s).tr("-_", " ").squeeze(" ").strip
      rescue StandardError
        segment.to_s
      end

      def normalize_path(path)
        p = path.to_s
        p = p.chomp("/")
        p = "/#{p}" unless p.start_with?("/")
        p == "" ? "/" : p
      end

      def score_content(stats)
        score = 0
        notes = []

        chars = stats[:char_count]
        case chars
        when 3_000.. then score += 45; notes << "本文量は十分"
        when 1_800...3_000 then score += 35; notes << "本文量は標準的"
        when 900...1_800 then score += 22; notes << "本文がやや少ない"
        when 300...900 then score += 10; notes << "本文が短い"
        else score += 3; notes << "コンテンツ量が不足"
        end

        h2 = stats[:h2_count]
        case h2
        when 4..12 then score += 30; notes << "見出し構成が適切"
        when 2..3, 13..18 then score += 18; notes << "見出し数を調整するとよい"
        when 1 then score += 8; notes << "H2が少ない"
        else score += 4; notes << "見出し構造が弱い"
        end

        score += 15 if stats[:h3_count].between?(2, 20)
        score += 10 if stats[:paragraph_count] >= 5
        score = [score, 100].min

        { score: score, note: notes.first(2).join(" / ") }
      end

      def score_basic_seo(doc, stats)
        score = 0
        notes = []

        title_len = stats[:title_length]
        if title_len.between?(28, 65)
          score += 22
          notes << "title長が適切"
        elsif title_len.between?(15, 80)
          score += 12
          notes << "title長を調整可能"
        elsif title_len.positive?
          score += 5
          notes << "titleが短すぎ／長すぎ"
        else
          notes << "title未設定"
        end

        desc_len = stats[:meta_description_length]
        if desc_len.between?(70, 160)
          score += 22
          notes << "description良好"
        elsif desc_len.between?(40, 200)
          score += 12
        elsif desc_len.zero?
          notes << "meta description未設定"
        end

        case stats[:h1_count]
        when 1 then score += 18
        when 2..3 then score += 8; notes << "H1が複数"
        else notes << "H1が無い／多すぎ"
        end

        score += 10 if stats[:has_canonical]
        score += 8 if stats[:has_og_title]
        score += 8 if stats[:has_viewport]
        score += 6 if stats[:has_json_ld]

        if stats[:image_count].positive?
          ratio = stats[:images_with_alt].to_f / stats[:image_count]
          score += (ratio * 6).round
          notes << "画像altが不足" if ratio < 0.6
        end

        score = [score, 100].min
        { score: score, note: notes.first(2).join(" / ").presence || "基本タグを確認" }
      end

      def score_specificity(doc, stats)
        score = 20
        notes = []
        sample = stats[:body_text_sample].to_s

        number_hits = sample.scan(/\d+(?:[\.,]\d+)?%?|円|万円|社|件|年|月/).size
        if number_hits >= 8
          score += 25
          notes << "具体的な数値・事実が多い"
        elsif number_hits >= 3
          score += 15
          notes << "具体例が一定ある"
        else
          notes << "数値・具体例が少ない"
        end

        if stats[:list_count] >= 2
          score += 15
          notes << "リストで整理されている"
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
            host.present? && page_host.present? && host != page_host
          rescue StandardError
            false
          end
        end
        if external_links >= 2
          score += 12
          notes << "外部参照リンクあり"
        end

        author_or_date = doc.at_css('time, [itemprop="datePublished"], [rel="author"], .author, .byline')
        score += 10 if author_or_date
        score += 8 if sample.match?(/例えば|具体的|手順|ステップ|ポイント|まとめ/)
        score += 10 if stats[:char_count] >= 2_000 && stats[:h2_count] >= 3

        score = [score, 100].min
        { score: score, note: notes.first(2).join(" / ").presence || "具体性の補強余地あり" }
      end

      def score_cluster(cluster_info, breadcrumbs)
        score = cluster_info[:confidence]
        notes = []

        if cluster_info[:pillar_candidate].present? && cluster_info[:cluster_candidate].present?
          notes << "ピラー候補「#{cluster_info[:pillar_candidate]}」"
        end
        notes.concat(cluster_info[:evidence].first(2))

        if breadcrumbs.size < 2 && cluster_info[:depth] < 2
          notes << "パンくず／ジャンル階層が見つからない"
        end

        { score: score, note: notes.first(2).join(" / ").presence || "クラスター構造は推定弱" }
      end

      def build_improvements(axes, stats, cluster_info)
        tips = []

        tips << "本文を増やし、検索意図を満たす具体情報を追加しましょう（現在おおよそ#{stats[:char_count]}文字）" if axes[:content][:score] < 70
        tips << "H2を4〜8個程度に整え、トピックを深掘りしましょう" if stats[:h2_count] < 3
        tips << "meta description（70〜160文字）を設定しましょう" if stats[:meta_description_length] < 40
        tips << "H1はページに1つだけ置き、タイトルと整合させましょう" if stats[:h1_count] != 1
        tips << "数値・手順・事例を入れて内容の具体性を高めましょう" if axes[:specificity][:score] < 65
        tips << "パンくずリスト（BreadcrumbList）を実装し、ジャンル→ピラー→クラスターの階層を明示しましょう" if axes[:cluster][:score] < 50
        tips << "クラスター記事からピラー（親）ページへの内部リンクを追加しましょう" if cluster_info[:pillar_candidate].present? && !cluster_info[:links_to_parent]
        tips << "canonical / OGP など基本タグを補強しましょう" if axes[:basic_seo][:score] < 70

        tips.first(3)
      end
    end
  end
end
