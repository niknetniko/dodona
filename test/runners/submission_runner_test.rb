require 'json'
require 'test_helper'
require 'timeout'

class SubmissionRunnerTest < ActiveSupport::TestCase
  setup do
    @repository = create :repository, :git_stubbed
    @judge = @repository.judge
    @course = create :course
    @user = create :user, courses: [@course]
    @series = create :series, course: @course
    @exercise = create :exercise,
                       :config_stubbed,
                       series: [@series],
                       repository: @repository
    @submission = create :submission,
                         user: @user,
                         course: @course,
                         exercise: @exercise
  end

  STRIKE_ERROR = 'DE HAVENVAKBOND STAAKT!!1!'.freeze

  def evaluate_with_stubbed_docker(obj = nil, **kwargs)
    obj = docker_mock(kwargs) unless obj
    Docker::Container.stubs(:create).returns(obj)
    @submission.evaluate
  end

  def docker_mock(**params)
    default_params = {
      status_code: 0,
      output: {
        accepted: true,
        status: 'correct'
      }
    }

    params = default_params.merge(params)

    stdout = if params[:output].is_a?(Hash)
               params[:output].to_json
             else
               params[:output].to_s
             end

    obj = mock
    obj.stubs(:start)
    obj.stubs(:delete)
    obj.stubs(:attach).returns([[stdout], [params[:err]]])
    obj.stubs(:wait).returns('StatusCode' => params[:status_code])
    obj
  end

  def assert_submission(status: nil, summary: nil, message_includes: nil, accepted: true)
    assert_not_nil @submission.result, 'There should always be a result'
    assert_equal status, @submission.status, 'Wrong submission status'
    summary ||= I18n.t("activerecord.attributes.submission.statuses.#{status}")
    assert_equal summary, @submission.summary, 'Wrong submission summary'
    if message_includes
      result = JSON.parse(@submission.result)
      messages = result['messages']
      message_contents = messages.map { |m| m['description'] }
      included = message_contents.any? { |m| m.include?(message_includes) }
      assert included,
             "Expected to find the text \n\"#{message_includes}\"\n" \
             "In one of the following messages of result:\n" \
             "#{message_contents}"
    end

    assert_equal accepted, @submission.accepted
  end

  test 'judge should receive merged config' do
    @exercise.update(programming_language: 'whitespace')
    @exercise.unstub(:config)
    # Stub global config
    File.stubs(:read)
        .with(Rails.root.join('app', 'runners', 'config.json'))
        .returns({
          memory_limit: 100,
          time_limit: 42,
          network_enabled: false
        }.to_json)
    # Overide something
    @exercise.stubs(:config).returns({
      evaluation: { network_enabled: true }.stringify_keys
    }.stringify_keys)
    mock = docker_mock
    mock.unstub(:attach)
    config = {}
    mock.expects(:attach).with do |args|
      config = JSON.parse(args[:stdin].read)
      true
    end
    evaluate_with_stubbed_docker mock
    assert_equal 100, config['memory_limit']
    assert_equal 42, config['time_limit']
    assert_equal true, config['network_enabled'] # overidden
    assert_equal @exercise.programming_language, config['programming_language']
    assert_equal @user.lang, config['natural_language']
    %w[resources source judge workdir].each do |key|
      path = config[key]
      assert_not_nil path
      assert path.starts_with?('/'), "Expected config[#{key}] to be an absolute path, but was '#{path}'"
    end
  end

  test 'submission evaluation should start docker container' do
    Docker::Container.expects(:create).once
    @submission.evaluate
  end

  test 'correct submission should be accepted and correct' do
    summary = 'Wow. Such code. Many variables.'
    evaluate_with_stubbed_docker output: {
      accepted: true,
      status: 'correct',
      description: summary
    }
    assert_submission status: 'correct', summary: summary, accepted: true
  end

  test 'compilation error should not be accepted' do
    summary = 'Something something lifetimes.'
    evaluate_with_stubbed_docker output: {
      accepted: false,
      status: 'compilation error',
      description: summary
    }
    assert_submission status: 'compilation error', summary: summary, accepted: false
  end

  test 'runtime error should not be accepted' do
    summary = 'Could not compile exe.java'
    evaluate_with_stubbed_docker output: {
      accepted: false,
      status: 'runtime error',
      description: summary
    }
    assert_submission status: 'runtime error', summary: summary, accepted: false
  end

  test 'docker container should be deleted after use' do
    docker = docker_mock
    docker.expects(:delete)
    evaluate_with_stubbed_docker(docker)
  end

  test 'malformed json should result in internal error' do
    skip
    evaluate_with_stubbed_docker output: 'DIKKE TAARTEN!!1!'

    assert_submission status: 'internal error',
                      message_includes: 'Failed to parse the following JSON',
                      accepted: false
  end

  test 'no output should result in internal error' do
    skip
    evaluate_with_stubbed_docker output: nil
    assert_submission status: 'internal error',
                      message_includes: 'No judge output',
                      accepted: false
  end

  test 'non-zero status code should result in internal error' do
    evaluate_with_stubbed_docker status_code: 1,
                                 err: STRIKE_ERROR

    assert_submission status: 'internal error',
                      message_includes: STRIKE_ERROR,
                      accepted: false
  end

  test 'timeout without output should result in time limit exceeded' do
    skip
    evaluate_with_stubbed_docker output: nil, status_code: 143
    assert_submission status: 'time limit exceeded',
                      accepted: false
  end

  test 'timeout with broken output should result in time limit exceeded' do
    skip
    evaluate_with_stubbed_docker output: '{ status: "Aarhhg...',
                                 status_code: 143
    assert_submission status: 'time limit exceeded',
                      accepted: false
  end

  test 'submissions eating RAM should result in memory limit exceeded' do
    evaluate_with_stubbed_docker status_code: 1, err: 'got signal 9'

    assert_submission status: 'memory limit exceeded',
                      accepted: false
  end

  test 'error in docker creation should result in internal error' do
    Docker::Container.stubs(:create).raises(STRIKE_ERROR)

    @submission.evaluate

    assert_submission status: 'internal error',
                      message_includes: "Error creating docker: #{STRIKE_ERROR}",
                      accepted: false
  end

  test 'random errors should be caught' do
    docker = docker_mock
    docker.stubs(:start).raises(STRIKE_ERROR)
    evaluate_with_stubbed_docker(docker)

    assert_submission status: 'internal error',
                      message_includes: STRIKE_ERROR,
                      accepted: false
  end
end