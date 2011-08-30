package Mojolicious::Plugin::PortableContacts::Response;
use Mojolicious::Plugin::PortableContacts::Entry;
use strict;
use warnings;

use Mojolicious::Plugin::XML::Serial;
use Mojo::JSON;

our @RESPONSE;
BEGIN {
    our @RESPONSE = qw/startIndex itemsPerPage totalResults/;
};

# Todo! Allow other valid values

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
};

sub to_json {
    my $self = shift;
    my %response;

    foreach (@RESPONSE) {
	$response{$_} = $self->{$_} if exists $self->{$_};
    };

    if ($self->{entry}) {
	if (ref($self->{entry}) eq 'ARRAY') {

	    if ($self->{entry}->[0]) {
		my @entries;
		foreach ( @{ $self->{entry} } ) {
		    push (@entries,
			  $self->new_entry($_)->to_json);
		};
		$response{'entry'} = \@entries;
	    };
	}
	
	elsif (ref($self->{entry}) eq 'HASH' && exists $self->{entry}->{id}) {
	    $response{entry} = Mojolicious::Plugin::PortableContacts::Entry->new
		($self->{entry}
		)->to_json
	};
    }; 
    return Mojo::JSON->new->encode(\%response);
};

sub to_xml {
    my $self = shift;
    my $response = Mojolicious::Plugin::XML::Serial->new('response');

    my %hash;
    foreach (@RESPONSE) {
	$response->add($_ => $self->{$_}) if exists $self->{$_};
    };

    if ($self->{entry}) {
	if (ref($self->{entry}) eq 'ARRAY') {
	    if ($self->{entry}->[0]) {
		foreach ( @{ $self->{entry} } ) {
		    $response->add(
			Mojolicious::Plugin::PortableContacts::Entry
			->new($_)
			->to_xml
			);
		};
	    };
	    
	}
	
	elsif (ref($self->{entry}) eq 'HASH' &&
	       exists $self->{entry}->{id}) {
	    $response->add(
		Mojolicious::Plugin::PortableContacts::Entry
		->new($self->{entry})
		->to_xml
		);
	};
    };
 
    return $response->to_pretty_xml;
};

1;
