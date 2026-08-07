class ProblemMailer < ApplicationMailer
  default to: "info@j-work.jp"

  def report_email(problem)
    @problem = problem

    if @problem.photo.present? && @problem.photo.file.present?
      filename = @problem.photo.identifier.presence || File.basename(@problem.photo.path.to_s)
      attachments.inline[filename] = File.binread(@problem.photo.path)
      @photo_attachment_name = filename
    end

    mail(
      to: "info@j-work.jp",
      from: @problem.email,
      subject: "【Drafity問題報告】#{@problem.company}様より"
    )
  end
end
