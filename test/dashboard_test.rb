ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require "yaml"

require_relative "../dashboard"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end
    
  def setup
    FileUtils.mkdir_p(current_clients)
    FileUtils.mkdir_p(archived_clients)
    File.write(task_path, '[]')
    File.write(event_path, '[]')
  end

  def teardown
    FileUtils.rm_rf("public")
    File.delete(task_path)
    File.delete(event_path)
  end
  
  def add_task(title, schedule, frequency)
    task = {title: title, schedule: schedule, frequency: frequency}
    task[:delete_on] = (Date.today + 7) if frequency == "this_week"
    
    custom_tasks = YAML.load_file(task_path)
    custom_tasks << task
    File.write(task_path, custom_tasks.to_yaml)
  end
  
  def test_index
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no tasks today"
    
    add_task("Test Task", [today], "every_week")
    
    assert_includes last_response.body, "Test Task"
  end
  
end