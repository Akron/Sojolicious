package Mojolicious::Plugin::Atom;
use Mojo::Base 'Mojolicious::Plugin::XML::Simple';
use strict;
use warnings;

sub new {
    my $class = shift;
    my $type = shift;
    $type ||= 'feed';
    my $tree = [
	'root',
	[ 'pi', 'xml '.
                'version="1.0" '.
                'encoding="UTF-8" '.
                'standalone="yes"' ],
	[ 'tag',
	  $type,
	  { 'xmlns' => 'http://www.w3.org/2005/Atom' }
	]
	];

    return $class->SUPER::new($tree);
};

sub add_author {
    my $self = shift;
    my %data = @_;
    my $author = $self->add('author');
    foreach (keys %data) {
	$author->add($_ => $data{$_} ) if $data{$_};
    };
    return $author;
};

sub add_entry {
    my $self = shift;
    my $entry = $self->add('entry');
    $entry->add('id', shift ) if $_[0];
    $entry->comment('Feed-Entry');
    return $entry;
};

1;

__END__



element :id, :rights, :icon, :logo
    element :generator, :class => Atom::Generator
    element :title, :subtitle, :class => Atom::Content
    element :updated, :class => Time, :content_only => true
    elements :links, :class => Atom::Link
    elements :authors, :class => OStatus::Author
    elements :categories, :class => Atom::Category
    elements :entries, :class => OStatus::Entry

