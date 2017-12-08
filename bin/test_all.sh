#!/usr/bin/env bash

HAS_JRUBY=$(ruby -v | grep -o jruby)
if [[ $HAS_JRUBY = "jruby"  ]]; then
  JRUBY_OPTS="--debug" jruby -I vendor/bundle spec/test_all.rb
else
  bundle exec ruby spec/test_all.rb
fi
