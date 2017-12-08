#!/usr/bin/env bash

HAS_JRUBY=$(ruby -v | grep -o jruby)
if [[ $HAS_JRUBY = "jruby"  ]]; then
  echo "Using ${BUNDLE_PATH:-vendor/bundle} for an include path"
  JRUBY_OPTS="--debug" jruby -I "${BUNDLE_PATH:-vendor/bundle}" spec/test_all.rb
else
  bundle exec ruby spec/test_all.rb
fi
