# Ruby Style Guide

Personal style preference when developing with Ruby. While this configuration is mostly copied from a certain repository of my own, I felt that having a personalized consistent programming style is much better despite how the time passes. Maybe, the Explanation, reasoning, exact table list will written later on.

## Adoption with RuboCop

Inside `Gemfile`:
```ruby
gem "rubocop-bloom_jewel", require: false
```

Prepend on top of project's RuboCop config:
```ruby
inherit_gem:
  rubocop-bloom_jewel:
  - config/general.yml
```