module ApplicationHelper
  def default_meta_tags
    {
      site: "豊富な人材集客力で企業の人材不足を解消|『J Work』",
      description: "豊富な人材集客力で企業の人材不足を解消|『J Work』。軽貨物・警備・建設・清掃業等様々な業界で活躍しています。",
      canonical: request.original_url,  # 優先されるurl
      charset: "UTF-8",
      reverse: true,
      separator: '|',
      icon: [
        { href: image_url('favicon.ico') },
        { href: image_url('favicon.ico'),  rel: 'apple-touch-icon' },
      ],

    }
  end

  def service_genre_sub_category_items(service_genre)
    submitted = params.dig(:service_genre, :sub_categories_items)
    return normalize_sub_category_items(submitted) if submitted.present?

    service_genre.sub_categories_for_form
  end

  def normalize_sub_category_items(items)
    Array(items).map do |item|
      item = item.to_unsafe_h if item.respond_to?(:to_unsafe_h)
      item = item.with_indifferent_access
      {
        key: item[:key],
        name: item[:name],
        target: item[:target],
        description: item[:description],
        features_text: item[:features_text],
        keywords_text: item[:keywords_text],
        price_hint: item[:price_hint],
        area: item[:area],
        strengths: item[:strengths],
        industry_weakness: item[:industry_weakness]
      }
    end
  end
end
