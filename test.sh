#!/bin/bash

zig build test -Dmigration_root_path=./tests/migrations/ -Dminify_sql --summary all
