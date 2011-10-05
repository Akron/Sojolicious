package Mojolicious::Plugin::Date::RFC822;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

require Time::Local;

has 'epoch';

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
