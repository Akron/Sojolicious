package Mojolicious::Plugin::PortableContacts::Response;
use Mojo::Base -base;
use Mojolicious::Plugin::PortableContacts::Entry;
use Mojolicious::Plugin::XML::Serial;
use Mojo::JSON;

# Todo! Allow other valid values
our @RESPONSE;
BEGIN {
    our @RESPONSE = qw/startIndex itemsPerPage totalResults/;
};

has \@RESPONSE => 0;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    if (exists $self->{entry}) {

	# Multiple contacts
	if (ref($self->{entry}) eq 'ARRAY') {
	    $self->{entry} = [
		map(
		    $self->new_entry($_),
		    @{$self->{entry}}
		)];
	}

	# Single contact
	elsif (ref($self->{entry}) eq 'HASH') {
	    $self->{entry} =
		$self->new_entry($self->{entry});
	};
    };

    return $self;
};

sub new_entry {
    shift;
    if (ref($_[0]) eq
	'Mojolicious::Plugin::PortableContacts::Entry') {
	return $_[0];
    } else {
	return Mojolicious::Plugin::PortableContacts::Entry->new(@_);
    };
};


# Get entry values
sub entry {
    my $self = shift;
    return unless $self->{totalResults};

    # Always return an array ref
    my $entry = $self->{entry};
    return $entry if ref($entry) eq 'ARRAY';
    return [$entry];
};

# Return JSON document
sub to_json {
    my $self = shift;
    my %response;

    foreach (@RESPONSE) {
	$response{$_} = $self->{$_} if exists $self->{$_};
    };

    if ($self->{entry}) {

	# Multiple entries
	if (ref($self->{entry}) eq 'ARRAY') {
	    my @entries;
	    foreach ( @{ $self->{entry} } ) {
		next unless exists $_->{id};
		push (@entries, $_->_json );
	    };
	    $response{entry} = \@entries;
	}
	
	# Single entries
	elsif (ref($self->{entry}) eq 'HASH' &&
	       exists $self->{entry}->{id}) {
	    $response{entry} = $self->{entry}->_json
	};
    }; 
    return Mojo::JSON->new->encode(\%response);
};

# Return XML document
sub to_xml {
    my $self = shift;
    my $response = Mojolicious::Plugin::XML::Serial->new('response');

    my %hash;
    foreach (@RESPONSE) {
	$response->add($_ => $self->{$_}) if exists $self->{$_};
    };

    if ($self->{entry}) {

	# Multiple entries
	if (ref($self->{entry}) eq 'ARRAY') {
	    foreach ( @{ $self->{entry} } ) {
		next unless exists $_->{id};
		$response->add($_->_xml);
	    };
	}
	
	# Single entries
	elsif (ref($self->{entry}) eq 'HASH' &&
	       exists $self->{entry}->{id}) {
	    $response->add($self->{entry}->_xml);
	};
    };
 
    return $response->to_pretty_xml;
};

1;

__END__

Mojolicious::Plugin::PortableContacts::Response
