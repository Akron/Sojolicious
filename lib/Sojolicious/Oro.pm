package Sojolicious::Oro;
use strict;
use warnings;
use Carp qw/carp/;

# Constructor
sub new {
  shift;
  carp __PACKAGE__ . ' is deprecated in favor of DBIx::Oro';
  return DBIx::Oro->new(@_);
};

1;

__END__

Deprecated!
