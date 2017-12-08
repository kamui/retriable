#!/usr/bin/env bash

HAS_JRUBY=$(ruby -v | grep -o jruby)
if [[ $HAS_JRUBY = "jruby"  ]]; then
  JRUBY_OPTS="--debug" BUNDLE_PATH=./vendor/bundle bundle exec jruby spec/test_all.rb
else
  bundle exec ruby spec/test_all.rb
fi
