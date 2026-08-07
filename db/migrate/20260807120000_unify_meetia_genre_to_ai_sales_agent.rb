# frozen_string_literal: true

# Meetia / ai_sales_agent が二重登録されていたのを ai_sales_agent に統一する。
# 旧キー meetia の参照はコード側の GENRE_KEY_ALIASES で互換維持する。
class UnifyMeetiaGenreToAiSalesAgent < ActiveRecord::Migration[6.1]
  OLD_KEY = "meetia"
  NEW_KEY = "ai_sales_agent"

  def up
    return unless table_exists?(:service_genres)

    say_with_time "unify service_genres #{OLD_KEY} → #{NEW_KEY}" do
      unify_service_genres!
    end

    say_with_time "rewrite columns.genre #{OLD_KEY} → #{NEW_KEY}" do
      rewrite_table_genre!(:columns) if table_exists?(:columns) && column_exists?(:columns, :genre)
    end

    say_with_time "rewrite autonomous_content_runs.genre #{OLD_KEY} → #{NEW_KEY}" do
      if table_exists?(:autonomous_content_runs) && column_exists?(:autonomous_content_runs, :genre)
        rewrite_table_genre!(:autonomous_content_runs)
      end
    end

    say_with_time "rewrite clients.allowed_genres #{OLD_KEY} → #{NEW_KEY}" do
      rewrite_allowed_genres! if table_exists?(:clients) && column_exists?(:clients, :allowed_genres)
    end

    GenreRegistry.reset! if defined?(GenreRegistry)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def unify_service_genres!
    client_ids = ServiceGenre.where(key: [OLD_KEY, NEW_KEY]).distinct.pluck(:client_id)

    client_ids.each do |client_id|
      scope = ServiceGenre.where(client_id: client_id)
      old_row = scope.find_by(key: OLD_KEY)
      new_row = scope.find_by(key: NEW_KEY)

      if old_row && new_row
        merge_attrs!(keeper: new_row, donor: old_row)
        old_row.destroy!
      elsif old_row && !new_row
        old_row.update!(key: NEW_KEY)
      end
    end
  end

  def merge_attrs!(keeper:, donor:)
    attrs = {}
    %i[ja service_name strong_points].each do |attr|
      next unless keeper.has_attribute?(attr)
      next if keeper.public_send(attr).to_s.strip.present?
      next if donor.public_send(attr).to_s.strip.blank?

      attrs[attr] = donor.public_send(attr)
    end

    if keeper.has_attribute?(:columns_index_description)
      if keeper.columns_index_description.to_s.strip.blank? && donor.columns_index_description.to_s.strip.present?
        attrs[:columns_index_description] = donor.columns_index_description
      end
    end

    %i[hosts keywords images].each do |attr|
      next unless keeper.has_attribute?(attr)
      next if Array(keeper.public_send(attr)).any?
      next if Array(donor.public_send(attr)).blank?

      attrs[attr] = donor.public_send(attr)
    end

    if keeper.has_attribute?(:sub_categories)
      keeper_subs = keeper.sub_categories
      donor_subs = donor.sub_categories
      if blank_hash?(keeper_subs) && !blank_hash?(donor_subs)
        attrs[:sub_categories] = donor_subs
      end
    end

    if keeper.has_attribute?(:column_cta)
      keeper_cta = keeper.column_cta
      donor_cta = donor.column_cta
      if blank_hash?(keeper_cta) && !blank_hash?(donor_cta)
        attrs[:column_cta] = donor_cta
      end
    end

    keeper.update!(attrs) if attrs.present?
  end

  def rewrite_table_genre!(table_name)
    model = table_name.to_s.classify.constantize
    model.where(genre: OLD_KEY).update_all(genre: NEW_KEY)
  rescue NameError
    execute ActiveRecord::Base.sanitize_sql_array(
      ["UPDATE #{table_name} SET genre = ? WHERE genre = ?", NEW_KEY, OLD_KEY]
    )
  end

  def rewrite_allowed_genres!
    Client.find_each do |client|
      list = Array(client.allowed_genres)
      next if list.blank?

      rewritten = list.map { |v| v.to_s == OLD_KEY ? NEW_KEY : v.to_s }.uniq
      next if rewritten == list.map(&:to_s)

      client.update_columns(allowed_genres: rewritten)
    end
  end

  def blank_hash?(value)
    value.blank? || (value.is_a?(Hash) && value.empty?)
  end
end
