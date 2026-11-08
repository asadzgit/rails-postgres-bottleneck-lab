require "test_helper"

class ReadinessTest < ActionDispatch::IntegrationTest
  test "root describes the JSON API" do
    get root_url
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "01-missing-index", response.parsed_body["experiment"]
  end

  test "Rails health endpoint responds successfully" do
    get "/up"
    assert_response :success
  end
end
