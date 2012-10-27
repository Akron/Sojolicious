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
        'Mojolicious' => 3.43,
        'DBIx::Oro'   => 0.21,
	'Test::More'  => 0
    },
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t'}
);

