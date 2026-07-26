require "test_helper"

class ColumnCrossClusterRelatedTest < ActiveSupport::TestCase
  def create_published!(attrs)
    Column.create!(
      {
        title: "t",
        body: "# body\n\ncontent",
        description: "desc",
        genre: "AI商談代行",
        code: "code-#{SecureRandom.hex(4)}",
        article_type: "child",
        published_at: Time.current,
        status: "completed"
      }.merge(attrs)
    )
  end

  test "returns articles from other clusters in same genre" do
    pillar_a = create_published!(title: "Pillar A", article_type: "pillar", parent_id: nil, code: "pillar-a-#{SecureRandom.hex(3)}")
    pillar_b = create_published!(title: "Pillar B", article_type: "pillar", parent_id: nil, code: "pillar-b-#{SecureRandom.hex(3)}")
    child_a = create_published!(title: "Child A", parent_id: pillar_a.id, code: "child-a-#{SecureRandom.hex(3)}", sub_genre: "ai_negotiation")
    child_b = create_published!(title: "Child B", parent_id: pillar_b.id, code: "child-b-#{SecureRandom.hex(3)}", sub_genre: "ai_negotiation")
    create_published!(title: "Sibling A2", parent_id: pillar_a.id, code: "sib-a2-#{SecureRandom.hex(3)}")

    related = Column.cross_cluster_related_to(child_a, limit: 6)
    related_ids = related.map(&:id)

    assert_includes related_ids, child_b.id
    assert_includes related_ids, pillar_b.id
    refute_includes related_ids, child_a.id
    refute_includes related_ids, pillar_a.id
  end
end
