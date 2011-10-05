package Mojolicious::Plugin::Date::RFC3339;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

require Time::Local;

has 'epoch';

# Based on Mojo::Date

# rfc3339 timestamp
my $RFC3339_RE = qr/^(\d{4})-(\d?\d)-(\d?\d)[Tt]
                     (\d?\d):(\d?\d):(\d?\d)(?:\.\d*)?
                     ([zZ]|[\-\+]?\d?\d(?::\d?\d)?)$/x;

# Constructor
sub new {
  my $self = shift->SUPER::new();
  $self->parse(@_);
  return $self;
};

# Parse date value
sub parse {
  my ($self, $date) = @_;

  return $self unless defined $date;

  if ($date =~ /^\d+$/) {
    $self->epoch($date);
  }

  elsif (my ($year, $month, $mday,
	     $hour, $min, $sec,
	     $offset) = ($date =~ $RFC3339_RE)) {
    my $epoch;
    $month--;

    eval {
      $epoch = Time::Local::timegm($sec, $min, $hour,
				   $mday, $month, $year);
    };

    # Calculate offsets
    if (uc($offset) ne 'Z' &&
	  (
	    my ($os_dir,
		$os_hour,
		$os_min) = ($offset =~ /^([-\+])(\d?\d)(?::(\d?\d))?$/))) {

      # Negative offset
      if ($os_dir eq '-') {
	$epoch += ($os_hour * 60 * 60) if $os_hour;
	$epoch += ($os_min * 60) if $os_min;
      }

      # Positive offset
      else {
	$epoch -= ($os_hour * 60 * 60) if $os_hour;
	$epoch -= ($os_min * 60) if $os_min;
      };
    };

    if (!$@ && $epoch > 0) {
      $self->epoch($epoch);
      return $self
    };
  };

  return $self;
};

# return string
sub to_string {
  my $self = shift;

  my $epoch = $self->epoch;
  $epoch = time unless defined $epoch;
  my ($sec, $min, $hour,
      $mday, $month, $year) = gmtime $epoch;

  # Format
  return sprintf(
    "%04d-%02d-%02dT%02d:%02d:%02dZ",
    ($year + 1900), ($month + 1), $mday,
    $hour, $min, $sec);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Date::RFC3339 - Support for RFC3339 dates

=head1 SYNOPSIS

  use Mojolicious::Plugin::Date::RFC3339;

  my $date = Mojolicious::Plugin::Date::RFC3339->new(784111777);
  my $date_str = $date->to_string;
  $date->parse('1993-01-01t18:50:00-04:00');
  my $epoch = $date->epoch;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Date::RFC3339> implements date and time functions
according to L<RFC3339|http://tools.ietf.org/html/rfc3339>.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Date::RFC3339> implements the following attributes.

=head2 C<epoch>

  my $epoch = $date->epoch;
  $date     = $date->epoch(784111777);

Epoch seconds.

=head1 METHODS

L<Mojolicious::Plugin::Date::RCF3339> inherits all methods from
L<Mojo::Base> and implements the following new ones.

=head2 C<new>

  my $date = Mojolicious::Plugin::Date::RFC3339->new;
  my $date = Mojolicious::Plugin::Date::RFC3339->new($string);

Construct a new L<Mojolicious::Plugin::Date::RFC3339> object.

=head2 C<parse>

  $date = $date->parse('1993-01-01t18:50:00-04:00');
  $date = $date->parse(1312043400);

=head2 C<to_string>

  my $string = $date->to_string;

Render date suitable to RFC3339 without offset information.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Time::Local>.

=head1 COPYRIGHT AND LICENSE

The code is heavily based on L<Mojo::Date>,
written by Sebastian Riedel. See L<Mojo::Date>
for additional copyright and license information.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
