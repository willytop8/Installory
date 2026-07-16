# -*- encoding: utf-8 -*-
# stub: fixture-native 1.15.4 arm64-darwin lib

Gem::Specification.new do |s|
  s.name = "fixture-native".freeze
  s.version = "1.15.4"
  s.platform = "arm64-darwin"
  s.require_paths = ["lib".freeze]
  s.rubygems_version = "3.5.7".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
    s.add_runtime_dependency(%q<fixture-runtime>.freeze, [">= 2.0".freeze])
    s.add_runtime_dependency(%q{fixture-parser}.freeze, ["~> 1.0".freeze])
  end
end
