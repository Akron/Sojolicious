package Sojolicious::ComplexValues;
use strict;
use warnings;
use Carp qw/carp/;

# Constructor
sub new {
  shift;
  carp __PACKAGE__ . ' is deprecated in favor of DBIx::Oro::ComplexValues';
  return DBIx::Oro::ComplexValues->new(@_);
};

1;

__END__

Deprecated!
