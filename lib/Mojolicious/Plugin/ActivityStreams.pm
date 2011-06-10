package Mojolicious::Plugin::ActivityStreams;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($plugin, $mojo, $param) = @_;

    $mojo->helper(
	'new_activity_stream' => sub {
	    return
		Mojolicious::Plugin::ActivityStreams::Document
		->new('feed');
	});

    $mojo->helper(
	'new_activity' => sub {
	    return
		Mojolicious::Plugin::ActivityStreams::Document
		->new('entry');
	});
};

# Todo: Helper for registering verbs

# Document class
package Mojolicious::Plugin::ActivityStreams::Document;
use Mojo::Base 'Mojolicious::Plugin::Atom';
use strict;
use warnings;

our ($as_ns);
BEGIN {
    our $as_ns = 'http://activitystrea.ms/schema/1.0/';
};

# Constructor
sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;
    my $type = shift;
    $type ||= 'feed';

    my $self = $class->SUPER::new($type);
    $self->dom->at($type)->attrs->{'xmlns:activity'} = $as_ns;

    return $self;
};

sub add_author {
    my $self = shift;
    my $author = $self->SUPER::add_author(@_);
    $author->add('activity:object-type', 'person');
    return $author;
};

sub add_verb {
    my $self = shift;
    return $self->add('activity:verb', shift);
};

sub add_object {
    my $self = shift;
    my %params = @_;
    my $object = $self->add('activity:object');
    $object->add('id', $params{id}) if exists $params{id};

    if (exists $params{type}) {
	$object->add('activity:object-type', $params{type});
    };

    return $object;
};

1;

__END__
