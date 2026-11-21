RSpec.describe "効果音を記録だけする印", type: :request do
  let(:marker) { 'name="sfx-record"' }

  it "sfx_record を設定していない環境（本番）では、印を出さずに音を鳴らさせる" do
    allow(Rails.configuration).to receive(:x).and_return(Rails::Application::Configuration::Custom.new)

    get new_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(marker)
  end

  it "sfx_record を true にした環境（test）だけ、印を出して音の名前を記録させる" do
    get new_session_path

    expect(response.body).to include(marker)
  end
end
