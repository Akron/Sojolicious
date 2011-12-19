#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    VERSION_FROM => "Readme.pod",
    NAME         => "Sojolicious",
    AUTHOR         => 'Nils Diewald',
    PREREQ_PM => {
        'Mojolicious' => 2.12,
        'DBD::SQLite' => 1.35,
        'DBI'         => 1.57
    }
);

