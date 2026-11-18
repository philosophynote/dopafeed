class JudgeReadingTiersByContent < ActiveRecord::Migration[8.1]
  RENAMES = { "common" => "normal", "jackpot" => "ss_rare" }.freeze

  def up
    change_column_null :readings, :tier, true
    RENAMES.each { |from, to| execute "UPDATE readings SET tier = #{quote(to)} WHERE tier = #{quote(from)}" }
  end

  # 旧版は 3 段で、空の tier を持てない。
  def down
    execute "UPDATE readings SET tier = 'rare' WHERE tier = 's_rare'"
    RENAMES.each { |from, to| execute "UPDATE readings SET tier = #{quote(from)} WHERE tier = #{quote(to)}" }
    execute "UPDATE readings SET tier = 'common' WHERE tier IS NULL"
    change_column_null :readings, :tier, false
  end
end
