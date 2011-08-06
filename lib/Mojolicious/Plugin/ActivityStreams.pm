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
use Mojolicious::Plugin::Atom;
use Mojo::Base 'Mojolicious::Plugin::Atom::Document';

our ($as_ns);
BEGIN {
    $as_ns = 'http://activitystrea.ms/schema/1.0/';
};

# Constructor
sub new {
    my $class = ref( $_[0] ) ? ref( shift(@_) ) : shift;

#    warn('~~ '.$class.'-'.join(',', '' ,@_));

    my $self = $class->SUPER::new(@_);
#    warn('*** '. $self->to_pretty_xml);


#    $self->add_ns('activity' => 'test');

    use Data::Dumper;
    warn(Dumper($self->tree));

    return $self;

#    my $self;

    if (ref($class)) {
	$self = $class->SUPER::new(@_);
    }

    else {
	# Use constructor from parent class
	$self = $class->SUPER::new(@_);
    };

    use Data::Dumper;
warn '!!! '.Dumper($self->tree).' !!!';

#    $self->add_ns('activity' => $as_ns);

    return $self;
};

# add activity streams author
sub add_author {
    my $self = shift;
    my $author = $self->SUPER::add_author(@_);
    $author->add('activity:object-type', 'person');
    return $author;
};

# add activity streams verb
sub add_verb {
    my $self = shift;
    return $self->add('activity:verb', shift);
};

# add activity streams object
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
