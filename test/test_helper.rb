# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 80, branch: 80
end

require "minitest/autorun"
require "minitest/spec"
require "mocha/minitest"

Mocha.configure { |c| c.stubbing_non_existent_method = :prevent }
