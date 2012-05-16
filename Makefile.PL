#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    VERSION_FROM => 'Readme.pod',
    NAME         => 'Sojolicious',
    AUTHOR       => 'Nils Diewald',
    PREREQ_PM => {
        'Mojolicious' => 2.40,
        'DBD::SQLite' => 1.33,
        'DBI'         => 1.57
    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t'}
);

