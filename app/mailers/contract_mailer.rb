class ContractMailer < ActionMailer::Base
  # 修正：必ずドメインを含む正しいアドレスを指定する
  default from: "info@j-work.jp" # 仮のドメインを入れています。実際の運用アドレスに

  def received_email(contract)
    @contract = contract
    # 修正：引数にまとめて設定を書く
    mail(
      from: @contract.email,
      to: "info@j-work.jp", # ここも正しいドメイン付きアドレスに
      subject: '株式会社J Workにお問い合わせがありました'
    )
  end

  def send_email(contract)
    @contract = contract
    mail(
      to: @contract.email,
      subject: 'お問い合わせ頂きありがとうございます。'
    )
  end
end