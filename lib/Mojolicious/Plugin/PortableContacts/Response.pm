package Mojolicious::Plugin::PortableContacts::Response;
use Mojo::Base -base;
use Mojo::JSON;
use XML::Loy;
use Mojolicious::Plugin::PortableContacts::Entry;

# Todo: Allow other valid values
my @RESPONSE = qw/startIndex itemsPerPage totalResults/;


# Constructor
sub new {
  my $class = shift;
  my $self = $class->SUPER::new( @_ );

  if (exists $self->{entry}) {

    # Multiple contacts
    if (ref($self->{entry}) eq 'ARRAY') {
      $self->{entry} = [
	map(
	  _new_entry($_),
	  @{$self->{entry}}
	)];
    }

    # Single contact
    elsif (ref($self->{entry}) eq 'HASH') {
      $self->{entry} =
	_new_entry($self->{entry});
    };
  };

  return $self;
};


# Attribute itemsPerPage
sub items_per_page {
  my $self = shift;
  return $self->{itemsPerPage} unless $_[0];
  $self->{itemsPerPage} = shift;
};


# Attribute startIndex
sub start_index {
  my $self = shift;
  return $self->{startIndex} || 0 unless $_[0];
  $self->{startIndex} = shift;
};


# Attribute totalResults
sub total_results {
  my $self = shift;
  return $self->{totalResults} || 0 unless $_[0];
  $self->{totalResults} = shift;
};


# Get entry values
sub entry {
  my $self = shift;

  # Always return an array ref
  return [] unless $self->{totalResults};
  return $self->{entry} if ref($self->{entry}) eq 'ARRAY';
  return [$self->{entry}];
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
    elsif (exists $self->{entry}->{id}) {
      $response{entry} = $self->{entry}->_json
    };
  };

  my $x = Mojo::JSON->new->encode( \%response );

  return $x;
};


# Return XML document
sub to_xml {
  my $self = shift;

  my $response = XML::Loy->new('response');

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
    elsif (exists $self->{entry}->{id}) {
      $response->add($self->{entry}->_xml);
    };
  };

  return $response->to_pretty_xml;
};


# Private function for entry objects
sub _new_entry {
  # Is an entry already
  if (ref($_[0]) eq
	'Mojolicious::Plugin::PortableContacts::Entry') {
    return $_[0];
  }

  # Is no entry yet
  else {
    return Mojolicious::Plugin::PortableContacts::Entry->new( @_ );
  };
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::PortableContacts::Response

=head1 SYNOPSIS

  my $res = { entry => [
              { id => 15,
                name => {
                  givenName  => 'Bender',
                  familyName => 'Rodriguez'
                }
              }
            ]};

  my $response =
       Mojolicious::Plugin::PortableContacts::Response->new($res);

  print $response->to_xml;

=head1 DESCRIPTION

L<Mojolicious::Plugin::PortableContacts::Response> is the object
class of responses for L<Mojolicious::Plugin::PortableContacts>.

=head1 ATTRIBUTES

=head2 C<items_per_page>

  my $items = $response->items_per_page;
  $response->items_per_page(25);

Number of query result entries per page.

=head2 C<start_index>

  my $si = $response->start_index;
  $response->start_index(20);

Absolute start index of the query result entries.

=head2 C<total_results>

  my $total = $response->total_results;
  $response->total_results(5);

Number of query result entries in total.

=head2 C<entry>

  foreach (@{$response->entry}) {
    print $_->to_xml;
  };

Array ref of entries in the query results.
This will return an array ref, even if a single entry is expected.
The items are L<Mojolicious::Plugin::PortableContacts::Entry>
objects.

=head1 METHODS

=head2 C<to_json>

  my $res = $response->to_json;

Returns a JSON string representing the response.
The response will contain only valid keys.

=head2 C<to_xml>

  my $res = $response->to_xml;

Returns an XML string representing the response.
The response will contain only valid keys.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>,
L<Mojolicious::Plugin::PortableContacts::Entry>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
