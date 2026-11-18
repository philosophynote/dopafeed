RSpec.describe "効果音の audioSession（ADR 0025）" do
  it "app/javascript は navigator.audioSession に触れず、種類を iOS の既定に任せる" do
    # 添字・別名・Object.assign でも書き換えられるので、代入の形ではなく語そのものを見る
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].flat_map do |f|
      path = f.delete_prefix("#{Rails.root}/")
      File.foreach(f).with_index(1).filter_map do |line, no|
        "#{path}:#{no}: #{line.strip}" if !line.match?(%r{^\s*(//|/\*|\*)}) && line.sub(%r{//.*}, "").include?("audioSession")
      end
    end
    expect(offenders).to be_empty, "\"ambient\" を明示すると iOS 27 で消音を切っても鳴らなかった。audioSession には触れない（ADR 0025）:\n#{offenders.join("\n")}"
  end
end
