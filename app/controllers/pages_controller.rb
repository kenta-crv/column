class PagesController < ApplicationController
  before_action :set_breadcrumbs
  # app, ads, short 以外はカラムを表示
  before_action :set_columns, except: [:app, :ads, :short]
  before_action :initialize_contract

  # 各アクション（中身は空で各viewを自動呼び出し）
  def index; end
  def cargo; end
  def human; end
  def security; end
  def construction; end
  def cleaning; end
  def daily; end
  def housekeeping; end
  def baby; end
  def babysitter; end
  def event; end
  def logistics; end
  def app; end
  def ads; end
  def short; end

  private

  def initialize_contract
    @contract = Contract.new
  end

  def set_columns
    @columns = Column.order(created_at: :desc).limit(3)
  end

  def set_breadcrumbs
    # 修正：ドメインに応じたルートパスを取得
    add_breadcrumb 'トップ', current_root_path
    
    label = LpDefinition.label(action_name)
    add_breadcrumb label, request.path if label
  end

  # --- ドメインごとのルートパス判定ロジック ---
  def current_root_path
    case request.host
    when 'ri-plus.jp'
      # routes.rb で定義した as: :ri_plus_root に対応
      ri_plus_root_path
    when 'j-work.jp'
      # routes.rb で定義した as: :j_work_root に対応
      j_work_root_path
    else
      # いずれにも該当しない場合のフォールバック
      "/"
    end
  end
  # View側でも使いたい場合は helper_method として登録
  helper_method :current_root_path
end
