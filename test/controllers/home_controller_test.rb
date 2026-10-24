require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "未ログインなら root はログイン画面へ" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "ログイン済みなら root が開く" do
    sign_in_as(users(:one))
    get root_path
    assert_response :success
  end
end
