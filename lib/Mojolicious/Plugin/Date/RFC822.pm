package Mojolicious::Plugin::Date::RFC822;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

require Time::Local;

has 'epoch';

# Based on Mojo::Date

# Days
my @DAYS = qw/Sun Mon Tue Wed Thu Fri Sat/;
my $DAYS   = qr/(?:(?:Su|Mo)n|Wed|T(?:hu|ue)|Fri|Sat)/;

# Months
my %MONTHS;
my @MONTHS = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
@MONTHS{@MONTHS} = (0 .. 11);

# Zones
my %ZONE;
my $ZONE   = qr/(?:(?:GM|U)|(?:([ECMP])([SD])))T/;
@ZONE{qw/E C M P/} = (4..7);

my $RFC822_RE = qr/^\s*(?:$DAYS[a-z]*,)?\s*(\d+)\s+(\w+)\s+
                    (\d+)\s+(\d+):(\d+):(\d+)\s*(?:$ZONE)?\s*$/x;

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

  elsif (my ($mday, $month, $year,
	     $hour, $min, $sec,
	     $zone_1, $zone_2) = ($date =~ $RFC822_RE)) {

    my $epoch;
    $month = $MONTHS{$month};

    # Set timezone offset
    my $offset = 0;
    if ($zone_1) {
      $offset = $ZONE{$zone_1};
      $offset++ if $zone_2 eq 'S';
    };

    eval {
      $epoch = Time::Local::timegm($sec, $min, $hour,
				   $mday, $month, $year);
    };

    $epoch += ($offset * 60 * 60);

    if (!$@ && $epoch > 0) {
      $self->epoch($epoch);
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
      $mday, $month, $year, $wday) = gmtime $epoch;

  # Format
  return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
		 $DAYS[$wday],
		 $mday,
		 $MONTHS[$month],
		 $year + 1900,
		 $hour,
		 $min,
		 $sec);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::Date::RFC822 - Support for RFC822 dates

=head1 SYNOPSIS

  use Mojolicious::Plugin::Date::RFC822;

  my $date = Mojolicious::Plugin::Date::RFC822->new(1317832113);
  my $date_str = $date->to_string;
  $date->parse('Wed, 05 Oct 2011 09:28:33 PDT');
  my $epoch = $date->epoch;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Date::RFC822> implements date and time functions
according to L<RFC822|>.

=head1 ATTRIBUTES

L<Mojolicious::Plugin::Date::RFC822> implements the following attributes.

=head2 C<epoch>

  my $epoch = $date->epoch;
  $date     = $date->epoch(1317832113);

Epoch seconds.

=head1 METHODS

L<Mojolicious::Plugin::Date::RCF822> inherits all methods from
L<Mojo::Base> and implements the following new ones.

=head2 C<new>

  my $date = Mojolicious::Plugin::Date::RFC822->new;
  my $date = Mojolicious::Plugin::Date::RFC822->new($string);

Construct a new L<Mojolicious::Plugin::Date::RFC822> object.

=head2 C<parse>

  $date = $date->parse('Wed, 05 Oct 2011 09:28:33 PDT');
  $date = $date->parse(1317832113);

=head2 C<to_string>

  my $string = $date->to_string;

Render date suitable to RFC822 without offset information.

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
