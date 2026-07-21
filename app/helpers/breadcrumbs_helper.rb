module BreadcrumbsHelper
  def breadcrumbs
    @breadcrumbs ||= []
  end

  # ApplicationController と同じ :label キーに揃える（JSON-LD / 表示の不一致防止）
  def add_breadcrumb(label, path = nil)
    breadcrumbs << { label: label, path: path }
  end
end
