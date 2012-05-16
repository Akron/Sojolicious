#!/usr/bin/env perl
use Test::More tests => 176;
use strict;
use warnings;

$|++;

use lib 'lib', '../lib', '../../lib';

use_ok 'Sojolicious::Oro';
use_ok 'Sojolicious::Tree';

use Data::Dumper;

my $name  = 'node_db';
my $name2 = 'foobar_';

my $tree = Sojolicious::Tree->new(
  name    => $name2
);

ok($tree, 'Create Tree');

is($tree->oro->driver, 'SQLite', 'Oro driver');

is($tree->name, $name2, 'Name');
ok($tree->name($name), 'Name');

ok($tree->init_db, 'Initialize tree');

is($tree->inside_position, 'after',  'Inside position');
ok($tree->inside_position('before'), 'Inside position');
is($tree->inside_position, 'before', 'Inside position');
ok($tree->inside_position('after'),  'Inside position');

ok(!$tree->cache, 'No cache');

is($tree->cache_prefix, 'tree_' . lc $name . '_', 'Cache prefix');
ok($tree->cache_prefix('foobar_'), 'Cache prefix');
is($tree->cache_prefix, 'foobar_', 'Cache prefix');

ok(!$tree->tree_id,   'Tree id value');
ok($tree->tree_id(2), 'Tree id value');
is($tree->tree_id, 2, 'Tree id value');

my ($id1, $id2, $id3);

ok($id1 = $tree->insert({
  type   => 4,
  ref    => 6,
  label  => 'design'
}), 'Insert without parent or position');

ok($id2 = $tree->insert({
  type  => 4,
  ref   => 7,
  label => 'css',
  node  => $id1,
  position => 'inside'
}), 'Insert with inside');

ok($tree->insert({
  type   => 1001,
  ref    => 8,
  label  => 'homepage.htm',
  node  => $id2,
  position => 'before'
}), 'Insert with before');

ok($tree->insert({
  type  => 1001,
  ref   => 10,
  position => 'after',
  node  => $id2,
  label => 'index.htm'
}), 'Insert with after');

ok($id3 = $tree->insert({
  type  => 1001,
  ref   => 9,
  label => 'style.css',
  node => $id2
}), 'Insert with parent but without position');

my $temp_tree = $tree->subtree;

is($temp_tree->[0]->{ref}, 6,           'Subtree 1');
is($temp_tree->[1]->[0]->{ref}, 8,      'Subtree 2');
is($temp_tree->[2]->[0]->{ref}, 7,      'Subtree 3');
is($temp_tree->[2]->[1]->[0]->{ref}, 9, 'Subtree 4');
is($temp_tree->[3]->[0]->{ref}, 10,     'Subtree 5');

is_deeply($temp_tree, scalar $tree->subtree($id1), 'Subtree match');

$temp_tree = $tree->subtree($id2);

is($temp_tree->[0]->{ref}, 7, 'Subtree 7');
is($temp_tree->[1]->[0]->{ref}, 9, 'Subtree 8');

ok(!$tree->insert({
  node  => ['css'],
  type  => 1001,
  ref   => 16,
  label => 'new_style.css'
}), 'Insert with array');

ok($tree->insert({
  node   => ['design','css'],
  type   => 1001,
  ref    => 17,
  label  => 'new_style.css'
}), 'Insert with array');

ok($tree->insert({
  node     => ['design','css','style.css'],
  position => 'before',
  type     => 1001,
  ref      => 18,
  label    => 'first_style.css'
}), 'Insert with array');

ok($tree->insert({
  node     => ['design','css','first_style.css'],
  position => 'after',
  type     => 1001,
  ref      => 19,
  label    => 'after_first_style.css'
}), 'Insert with array');

ok($tree->insert({
  node     => ['design','css','after_first_style.css'],
  position => 'after',
  type     => 1001,
  ref      => 20,
  label    => 'after_after_first_style.css'
}), 'Insert with array');

my $path = $tree->path($id3);
is($path->[0]->{label}, 'design',    'Path 1');
is($path->[1]->{label}, 'css',       'Path 2');
is($path->[2]->{label}, 'style.css', 'Path 3');

my $children = $tree->children($id1);
is($children->[0]->{label}, 'homepage.htm', 'Children 1');
is($children->[1]->{label}, 'css',          'Children 2');
is($children->[2]->{label}, 'index.htm',    'Children 3');

my $sibling = $tree->siblings($id3);
is($sibling->[0]->{label}, 'new_style.css',               'Sibling 1');
is($sibling->[1]->{label}, 'first_style.css',             'Sibling 2');
is($sibling->[2]->{label}, 'after_first_style.css',       'Sibling 3');
is($sibling->[3]->{label}, 'after_after_first_style.css', 'Sibling 4');

is_deeply($tree->path(['design','css','style.css']),
	  $tree->path($id3),
	  'Path node array');

is_deeply($tree->children(['design','css']),
	  $tree->children($id2),
	  'Children node array');

is_deeply($tree->siblings(['design','css','style.css']),
	  $tree->siblings($id3),
	  'Siblings node array');

# Delete /css
is($tree->delete(2), 6, 'Delete nodes');
is(@{$tree->oro->select($name . '_node')}, 3, 'Tree nodes');
is(@{$tree->oro->select($name)}, 5, 'Tree nodes');

# Delete /homepage.htm
is($tree->delete(3), 1, 'Delete nodes');
is(@{$tree->oro->select($name . '_node')}, 2, 'Tree nodes');
is(@{$tree->oro->select($name)}, 3, 'Tree nodes');

# Delete /homepage.htm
is($tree->delete(1), 2, 'Delete nodes');
ok(!@{$tree->oro->select($name . '_node')}, 'Tree nodes');
ok(!@{$tree->oro->select($name)}, 'Tree nodes');

ok(!$tree->subtree, 'Subtree empty');

ok($tree->insert({
  label  => 'a'
}), 'Insert a');

ok($tree->insert({
  label  => 'a/a',
  node => ['a'],
  position => 'inside'
}), 'Insert a/a');

ok($tree->insert({
  label  => 'a/b',
  node => ['a','a/a'],
  position => 'after'
}), 'Insert a/b');

ok($tree->insert({
  label  => 'a/c',
  node => ['a','a/b'],
  position => 'after'
}), 'Insert a/c');

ok($tree->insert({
  label  => 'a/d',
  node => ['a','a/c'],
  position => 'after'
}), 'Insert a/d');

ok($tree->insert({
  label  => 'a/c/b',
  node => ['a','a/c'],
  position => 'inside'
}), 'Insert a/c/b');

ok($tree->insert({
  label  => 'a/c/a',
  node => ['a','a/c','a/c/b'],
  position => 'before',
  ref => 4
}), 'Insert a/c/a');

my ($x, $ref_array) = $tree->subtree;

is(@$ref_array, 1, 'Reference Count');
is($ref_array->[0], 4, 'Reference');

is($tree->delete(['a','a/c']), 3, 'Delete with path array');

($x, $ref_array) = $tree->subtree;
is(@$ref_array, 0, 'Reference Count');

ok($tree->insert({
  label  => 'a/c',
  node => ['a','a/b'],
  position => 'after'
}), 'Insert a/c');

ok($tree->insert({
  label  => 'a/c/a',
  node => ['a','a/c'],
  position => 'inside'
}), 'Insert a/c/a');


sub _check_undefs ($) {
  my $oro = shift;
  join('',
       sort {$a <=> $b}
	 map {$_->{id}}
	   @{$oro->select($name => ['id'] => {
	     parent => undef
	   })});
};

sub _check_distances ($$) {
  my $oro = shift;
  join('',
       sort {$a <=> $b}
	 map { $_->{distance} }
	   @{$oro->select($name => ['distance'] => {
	     id => shift
	   })})
};

# Move:
ok($tree->move({
  node     => 2,
  target   => 6
}), 'Move with ids and inside position'); # 1

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,6,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [2,7], 'Move test');

# Todo: This can be optimized!
ok($tree->move({
  node     => 2,
  target   => 7,
  position => 'after'
}), 'Move with ids and position'); # 2

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,6,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [7,2], 'Move test');

# Todo: This can be optimized!
ok($tree->move({
  node     => 3,
  target   => 2,
  position => 'before'
}), 'Move with ids and position'); # 3

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [6,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [7,3,2], 'Move test');

# Fails!
ok(!$tree->move({
  node     => 6,
  target   => 2,
  position => 'before'
}), 'Move with ids and position');

ok(!$tree->move({
  node     => 1,
  target   => 2
}), 'Move with ids');

ok($tree->move({
  node     => 7,
  target   => ['a']
}), 'Move with id and path'); # 4

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [7,6,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [3,2], 'Move test');

ok($tree->move({
  node     => 3,
  target   => ['a','a/d'],
  position => 'before'
}), 'Move with id and path'); # 5

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [7,6,3,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [2], 'Move test');

ok(!$tree->move({
  node     => 7,
  target   => ['a','a/a'],
  position => 'after'
}), 'Move with id and path, but path does not exist');

ok($tree->move({
  node     => 7,
  target   => ['a','a/c','a/a'],
  position => 'after'
}), 'Move with id and path'); # 6

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [6,3,5], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [2,7], 'Move test');

ok($tree->move({
  node     => ['a','a/d'],
  target   => 7,
  position => 'before'
}), 'Move with id and path'); #7

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [6,3], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [2,5,7], 'Move test');

ok($tree->move({
  node     => ['a','a/c'],
  target   => 3
}), 'Move with id and path'); # 8

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [2,5,7], 'Move test');

ok($tree->move({
  node     => ['a','a/b','a/c','a/a'],
  target   => 3,
  position => 'after'
}), 'Move with id and path');

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,2], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [5,7], 'Move test');

ok($tree->move({
  node     => ['a','a/b','a/c','a/c/a'],
  target   => ['a','a/b']
}), 'Move with paths');

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,2], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [7,6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(6) }],
  [5], 'Move test');

ok($tree->move({
  node     => ['a','a/b','a/c','a/d'],
  target   => ['a','a/a'],
  position => 'inside'
}), 'Move with paths');

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,2], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [7,6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(2) }],
  [5], 'Move test');

ok($tree->move({
  node     => ['a','a/b','a/c/a'],
  target   => ['a','a/a', 'a/d'],
  position => 'after'
}), 'Move with paths and position');

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3,2], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(2) }],
  [5,7], 'Move test');

ok($tree->move({
  node     => ['a','a/a'],
  target   => ['a','a/b', 'a/c'],
  position => 'before'
}), 'Move with paths and position');

is_deeply(
  [map { $_->{id} } @{ $tree->children(1) }],
  [3], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(3) }],
  [2,6], 'Move test');

is_deeply(
  [map { $_->{id} } @{ $tree->children(2) }],
  [5,7], 'Move test');

#   undef
#     |
#     1
#     |
#     3
#    / \
#   2   6
#  / \
# 5   7

is(_check_undefs($tree->oro) , '123567', 'Undefs okay');
is(_check_distances($tree->oro, 1), '0', 'Distance for 1');
is(_check_distances($tree->oro, 3), '01', 'Distance for 3');
is(_check_distances($tree->oro, 2), '012', 'Distance for 2');
is(_check_distances($tree->oro, 6), '012', 'Distance for 6');
is(_check_distances($tree->oro, 5), '0123', 'Distance for 5');
is(_check_distances($tree->oro, 7), '0123', 'Distance for 7');

ok($tree->delete(['a']), 'Delete Tree');

ok($tree->insert({
  label => 'a',
}), 'Insert a');

ok($tree->insert({
  label => 'b',
  node  => ['a']
}), 'Insert b');

ok($tree->insert({
  label    => 'c',
  node     => ['a','b'],
  position => 'after'
}), 'Insert c');

ok($tree->insert({
  label    => 'd',
  node     => ['a','b'],
  position => 'inside'
}), 'Insert d');

ok($tree->insert({
  label    => 'e',
  node     => ['a','b','d'],
  position => 'after'
}), 'Insert e');

ok($tree->move({
  node     => ['a','b'],
  target   => ['a','c'],
  position => 'inside'
}), 'Move with path arrays');

#   undef     undef
#     |         |
#     a         a
#    / \        |
#   b   c  ->   c
#  / \          |
# d   e         b
#              / \
#             d   e

is(join('', map { $_->{label} } @{$tree->path(4)}), 'acbd', 'Path');

ok($tree->insert({
  label    => 'f',
  node     => ['a','c','b'],
  position => 'after'
}), 'Insert f');

ok(($id1 = $tree->insert({
  label    => 'g',
  node     => ['a','c','b','d']
})), 'Insert g');

ok(($id2 = $tree->insert({
  label    => 'h',
  node     => ['a','c','b','d','g'],
  position => 'after'
})), 'Insert h');

#     undef        undef
#       |            |
#       a            a
#       |           / \
#       c          c   b
#      / \        /   / \
#     b   f  ->  f   d   e
#    / \            / \
#   d   e          g   h
#  / \
# g   h

ok($tree->move({
  node     => ['a','c','b'],
  target   => ['a','c'],
  position => 'after'
}), 'Move with path arrays');

is(join('', map { $_->{label} } @{$tree->path($id1)}), 'abdg', 'Path');
is(join('', map { $_->{label} } @{$tree->path($id2)}), 'abdh', 'Path');

# Here: tree_id => 4
my $tree_4 = $tree->tree(4);
ok($tree_4, 'Tree change');

ok($tree_4->insert({
  label => 'a',
}), 'Insert a');

ok($tree_4->insert({
  label => 'b',
  node  => ['a']
}), 'Insert b');

ok($tree_4->insert({
  label    => 'c',
  node     => ['a','b'],
  position => 'after'
}), 'Insert c');

ok($tree_4->insert({
  label    => 'd',
  node     => ['a','b'],
  position => 'inside'
}), 'Insert d');

ok($tree_4->insert({
  label    => 'e',
  node     => ['a','b','d'],
  position => 'after'
}), 'Insert e');

#     a
#    / \
#   b   c
#  / \
# d   e

ok($tree_4->move({
  node     => ['a','b'],
  target   => ['a','c'],
  position => 'inside'
}), 'Move with path arrays');

#     a        a
#    / \       |
#   b   c ->   c
#  / \         |
# d   e        b
#             / \
#            d   e

ok($tree_4->insert({
  label    => 'f',
  node     => ['a','c','b'],
  position => 'after'
}), 'Insert f');

ok(($id1 = $tree_4->insert({
  label    => 'g',
  node     => ['a','c','b','d']
})), 'Insert g');

#      a
#      |
#      c
#     / \
#    b   f
#   / \
#  d   e
#  |
#  g

ok(($id2 = $tree_4->insert({
  label    => 'h',
  node     => ['a','c','b','d','g'],
  position => 'after'
})), 'Insert h');

#        a
#        |
#        c
#       / \
#      b   f
#     / \
#    d   e
#   / \
#  g   h

ok($tree_4->move({
  node     => ['a','c','b'],
  target   => ['a','c'],
  position => 'after'
}), 'Move with path arrays');

#        a          a
#        |         / \
#        c        c   b
#       / \      /   / \
#      b   f    f   d   e
#     / \          / \
#    d   e        g   h
#   / \
#  g   h

is(join('', map { $_->{label} } @{$tree_4->path($id1)}), 'abdg', 'Path');
is(join('', map { $_->{label} } @{$tree_4->path($id2)}), 'abdh', 'Path');

#    undef
#      |
#      a
#     / \
#    c   b
#   /   / \
#  f   d   e
#     / \
#    g   h

ok($tree_4->delete(['a','b','d']), 'Delete on tree_id = 4');

#      2
#      |
#      a
#     / \
#    c   b
#   /   / \
#  f   d   e
#     / \
#    g   h

#    4
#    |
#    a
#   / \
#  c   b
#  |   |
#  f   e

is_deeply(
  [map { $_->{label} } @{ $tree->children(['a','b']) }],
  ['d','e'], 'Children Test on 2');

is_deeply(
  [map { $_->{label} } @{ $tree_4->children(['a','b']) }],
  ['e'], 'Children Test on 4');

is_deeply(
  [map { $_->{label} } @{ $tree->path(['a','b','d','g']) }],
  ['a','b','d','g'], 'Path Test on 2');

is_deeply(
  [map { $_->{label} } @{ $tree_4->path(['a','c','f']) }],
  ['a','c','f'], 'Path Test on 4');

is_deeply(
  [map { $_->{label} } @{ $tree->siblings(['a','b','d']) }],
  ['e'], 'Siblings Test on 2');

is_deeply(
  [map { $_->{label} } @{ $tree_4->siblings(['a','c']) }],
  ['b'], 'Siblings Test on 4');

ok($tree_4->move({
  node     => ['a','b'],
  target   => ['a','c','f']
}), 'Move with path arrays');

# 4-a-c-f-b-e

is_deeply(
  [map { $_->{label} } @{ $tree_4->path([qw/a c f b e/]) }],
  [qw/a c f b e/], 'Path Test on 4');

is_deeply(
  [map { $_->{label} } @{ $tree->children([qw/a b d/]) }],
  [qw/g h/], 'Children Test on 2');


my $tree_5 = $tree->tree(5);

my $id = undef;
foreach ('a' .. 'f') {
  ok($id = $tree_5->insert({
    label => $_,
    node  => $id
  }), 'Insert ' . $_ . ' tree 5');
};

is_deeply(join('',
	       map { $_->{label} } @{$tree_5->path($id)}),
	  join('','a' .. 'f'), 'Path for 5');

ok($tree_5->move({
  node     => ['a','b','c'],
  target   => ['a','b'],
  position => 'after'
}), 'Move within 5');

ok($tree_5->move({
  node     => ['a','c','d'],
  target   => ['a'],
  position => 'inside'
}), 'Move within 5');

is_deeply(
  join('',
       map { $_->{label} } @{$tree_5->path(20)}),
  'adef', 'Path for 5');

is_deeply(
  join('',
       map { $_->{label} } @{$tree_5->path(17)}),
  'ac', 'Path for 5');

is_deeply(
  join('',
       map { $_->{label} } @{$tree_5->path(16)}),
  'ab', 'Path for 5');

# print Dumper $tree_5->subtree;

__END__

print Dumper $tree->subtree(4 => -root);

print Dumper $tree->oro->select($name . '_combi' => { distance => 0 });

#print Dumper $tree->subtree(4 => -root);



subtree -> self->tree_id and root
subtree('root') -> self->tree_id and root
subtree(4 => 'root') -> 4 and root
subtree(4) -> self->tree_id and 4


# Real DB:
my $db_file = tmpnam();

# No more memory:
my $oro = Sojolicious::Oro->new($db_file);
$tree = Sojolicious::Tree->new(
  oro => $oro,
  name => $name
);

ok($tree, 'Create Tree');
ok($tree->init_db, 'Initialize tree');

Test with disconnect!

unlink $db_file;

__END__

# Test for callbacks!
# Test with tree_ids

