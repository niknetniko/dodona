module StubHelper
  # stub all git methods
  def stub_git(obj)
    obj.stubs(:pull)
    obj.stubs(:reset)
    obj.stubs(:clone_repo)
    obj.stubs(:repo_is_accessible).returns(true)
  end

  def stub_status(exercise, status)
    exercise.stubs(:status).returns(status)
    Exercise.statuses.keys.each do |key|
      exercise.stubs("#{key}?".to_sym).returns(key == status)
    end
  end

  def stub_all_exercises!
    config = { 'evaluation' => { 'time_limit' => 1 } }.freeze
    config_locations = { 'evaluation' => { 'time_limit' => 'config.json' } }.freeze
    description = 'ᕕ(ಠ_ಠ)ᕗ'
    solutions = { 'solution.py' => 'print(input())' }
    Exercise.any_instance.stubs(:solutions).returns(solutions)
    Exercise.any_instance.stubs(:config).returns(config)
    Exercise.any_instance.stubs(:config_locations).returns(config_locations)
    Exercise.any_instance.stubs(:update_config)
    Exercise.any_instance.stubs(:merged_config).returns(config)
    Exercise.any_instance.stubs(:merged_config_locations).returns(config_locations)
    Exercise.any_instance.stubs(:description_localized).returns(description)
  end

  refine FactoryBot::SyntaxRunner do
    include StubHelper
  end

  # somehow we need to set this to false for use with factory bot 5
  FactoryBot.use_parent_strategy = false
end
