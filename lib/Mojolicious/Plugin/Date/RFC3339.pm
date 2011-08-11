package Mojolicious::Plugin::Date::RFC3339;
use Mojo::Base -base;
use overload '""' => sub { shift->to_string }, fallback => 1;

require Time::Local;

has 'epoch';

# Based on Mojo::Date

our $RFC3339_RE;
BEGIN {
    # rfc3339 timestamp
    our $RFC3339_RE = qr/^(\d{4})-(\d?\d)-(\d?\d)[Tt]
                          (\d?\d):(\d?\d):(\d?\d)(?:\.\d*)?
                          ([zZ]|[\-\+]?\d?\d(?::\d?\d)?)$/x;
};

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
	    return $epoch
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


The code is heavily based on L<Mojo::Date>.
# Atom and XRD
L<RFC3339|http://tools.ietf.org/html/rfc3339>
