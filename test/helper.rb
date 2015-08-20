require 'pp'
require 'tempfile'
require 'fileutils'
require 'test/unit'

module Test
  module Unit
    # Appending TestCase class.
    class TestCase
      # Monkey patch of TestCase to define test method.
      #
      # @param desc [String] Test description.
      # @param impl [Proc]   Code block.
      def self.test(desc, &impl)
        define_method("test #{desc}", &impl)
      end
    end
  end
end
