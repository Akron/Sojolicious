use Test::More tests => 41;
use File::Temp qw/:POSIX/;
use strict;
use warnings;

$|++;

use lib '../lib';
use_ok 'Sojolicious::Oro';

my $db_file = tmpnam();

diag "Created temp file $db_file";

END {
  unlink $db_file;
};

my $oro = Sojolicious::Oro->new(
  $db_file => sub {
    shift->do('CREATE TABLE Name (
                 id             INTEGER PRIMARY KEY,
                 prename        TEXT NOT NULL,
                 surname        TEXT
              )');
  });

ok($oro, 'Created');
ok($oro->created, 'Created');

if ($oro->created) {
  $oro->do(
    'CREATE TABLE Content (
       id            INTEGER PRIMARY KEY,
       content       TEXT,
       title         TEXT
     )'
  );
};

ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');
{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content_unknown => {title => 'Hey!'}), 'Insert');
};

ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Name => { surname => 'Rodriguez'}), 'Insert');
};

ok($oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check!' }), 'Update');

ok(!$oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check not existent!' }), 'Update');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->update(Content_unknown =>
		     { content => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->update(Content =>
		     { content_unkown => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');
};

my $row;
ok($row = $oro->load(Content => { title => 'Check!' }), 'Load');

is ($row->{content}, 'This is changed content.', 'load');

ok($oro->insert(Content =>
		  { title => 'Another check!',
		    content => 'This is second content.' }), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Check!',
		    content => 'This is third content.' }), 'Insert');

my $array;
ok($array = $oro->select(Content => { title => 'Check!' }), 'Select');
is($array->[0]->{content}, 'This is changed content.', 'Select');
is($array->[1]->{content}, 'This is third content.', 'Select');

ok($row = $oro->load(Content => { title => 'Another check!' } ), 'Load');
is($row->{content}, 'This is second content.', 'Check');

is($oro->delete(Content => { title => 'Another check!' }), 1, 'Delete');
ok(!$oro->delete(Content => { title => 'Well.' }), 'Delete');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->select('Content_2'), 'Select');
};

$oro->select('Content' => sub {
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select');
	     });

my $once = 1;
$oro->select('Content' => sub {
	       ok($once--, 'Select Once');
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select Once');
	       return -1;
	     });

$oro->select('Name' => ['prename'] =>
	       sub {
		 ok(!exists $_[0]->{surname}, 'Fields');
		 ok($_[0]->{prename}, 'Fields');
	     });

ok($oro->update_or_insert( Content =>
			     { content => 'Das ist der vierte content.' } =>
			       { 'title' => 'Check!' }), # Changes two entries!
   'Update or Insert');

ok($oro->update_or_insert( Content =>
			     { content => 'Das ist der fuenfte content.' } =>
			       { 'title' => 'Noch ein Check!' }),
   'Update or Insert');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->update_or_insert( Content_unknown =>
				{ content => 'Das ist der fuenfte content.' } =>
				  { 'title' => 'Noch ein Check!' }),
     'Update or Insert');
};

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');


{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content => [qw/titles content/] =>
		     ['CheckBulk','Das ist der elfte content']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/] =>
		     ['CheckBulk','Das ist der zwoelfte content', 'Yeah']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/]), 'Bulk Insert');
};

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 8, 'Check Select');

ok($oro->delete('Content', { title => 'CheckBulk'}), 'Delete Table');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 3, 'Check Select');

__END__
