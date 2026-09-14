# frozen_string_literal: true

# 親記事プロンプト。言語ごとに1ファイル。
#   config/gpt_prompts/ja.yml
#   config/gpt_prompts/en.yml
#   config/gpt_prompts/hiragana.yml
#
# 追加言語は Column::LANGUAGES にコードを足し、同名の yml を置く。
class GptPromptPack
  ROOT = Rails.root.join("config", "gpt_prompts")

  def self.for(language = GptGenerationLocale.current)
    new(language)
  end

  def initialize(language)
    @language = Column.normalize_language(language)
  end

  attr_reader :language

  def path
    ROOT.join("#{@language}.yml")
  end

  def exist?(name)
    templates.key?(name.to_s)
  end

  def render(name, **locals)
    source = templates[name.to_s]
    unless source
      raise ArgumentError, "GPT prompt missing: #{path.relative_path_from(Rails.root)}##{name}"
    end

    ERB.new(source.to_s, trim_mode: "-").result_with_hash(locals.transform_keys(&:to_s))
  end

  def system_prompt(json_mode:)
    suffix = json_mode ? "system_json_suffix" : "system_text_suffix"
    parts = [render("system").to_s.rstrip]
    parts << render(suffix).to_s.rstrip if exist?(suffix)
    parts.join("\n")
  end

  private

  def templates
    @templates ||= begin
      raise ArgumentError, "GPT prompt missing: #{path.relative_path_from(Rails.root)}" unless path.exist?

      loaded = YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: true)
      loaded.is_a?(Hash) ? loaded.transform_keys(&:to_s) : {}
    end
  end
end
