use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;

my $schema = DBICTest->init_schema();

plan tests => 96;

eval { require DateTime::Format::MySQL };
my $NO_DTFM = $@ ? 1 : 0;

my @art = $schema->resultset("Artist")->search({ }, { order_by => 'name DESC'});

is(@art, 3, "Three artists returned");

my $art = $art[0];

is($art->name, 'We Are Goth', "Correct order too");

$art->name('We Are In Rehab');

is($art->name, 'We Are In Rehab', "Accessor update ok");

my %dirty = $art->get_dirty_columns();
is(scalar(keys(%dirty)), 1, '1 dirty column');
ok(grep($_ eq 'name', keys(%dirty)), 'name is dirty');

is($art->get_column("name"), 'We Are In Rehab', 'And via get_column');

ok($art->update, 'Update run');

my %not_dirty = $art->get_dirty_columns();
is(scalar(keys(%not_dirty)), 0, 'Nothing is dirty');

eval {
  my $ret = $art->make_column_dirty('name2');
};
ok(defined($@), 'Failed to make non-existent column dirty');
$art->make_column_dirty('name');
my %fake_dirty = $art->get_dirty_columns();
is(scalar(keys(%fake_dirty)), 1, '1 fake dirty column');
ok(grep($_ eq 'name', keys(%fake_dirty)), 'name is fake dirty');

my $record_jp = $schema->resultset("Artist")->search(undef, { join => 'cds' })->search(undef, { prefetch => 'cds' })->next;

ok($record_jp, "prefetch on same rel okay");

my $record_fn = $schema->resultset("Artist")->search(undef, { join => 'cds' })->search({'cds.cdid' => '1'}, {join => 'artist_undirected_maps'})->next;

ok($record_fn, "funny join is okay");

@art = $schema->resultset("Artist")->search({ name => 'We Are In Rehab' });

is(@art, 1, "Changed artist returned by search");

is($art[0]->artistid, 3,'Correct artist too');

lives_ok (sub { $art->delete }, 'Cascading delete on Ordered has_many works' );  # real test in ordered.t

@art = $schema->resultset("Artist")->search({ });

is(@art, 2, 'And then there were two');

ok(!$art->in_storage, "It knows it's dead");

dies_ok ( sub { $art->delete }, "Can't delete twice");

is($art->name, 'We Are In Rehab', 'But the object is still live');

$art->insert;

ok($art->in_storage, "Re-created");

@art = $schema->resultset("Artist")->search({ });

is(@art, 3, 'And now there are three again');

my $new = $schema->resultset("Artist")->create({ artistid => 4 });

is($new->artistid, 4, 'Create produced record ok');

@art = $schema->resultset("Artist")->search({ });

is(@art, 4, "Oh my god! There's four of them!");

$new->set_column('name' => 'Man With A Fork');

is($new->name, 'Man With A Fork', 'set_column ok');

$new->discard_changes;

ok(!defined $new->name, 'Discard ok');

$new->name('Man With A Spoon');

$new->update;

my $new_again = $schema->resultset("Artist")->find(4);

is($new_again->name, 'Man With A Spoon', 'Retrieved correctly');

is($new_again->ID, 'DBICTest::Artist|artist|artistid=4', 'unique object id generated correctly');

# Test backwards compatibility
{
  my $warnings = '';
  local $SIG{__WARN__} = sub { $warnings .= $_[0] };

  my $artist_by_hash = $schema->resultset('Artist')->find(artistid => 4);
  is($artist_by_hash->name, 'Man With A Spoon', 'Retrieved correctly');
  is($artist_by_hash->ID, 'DBICTest::Artist|artist|artistid=4', 'unique object id generated correctly');
  like($warnings, qr/deprecated/, 'warned about deprecated find usage');
}

is($schema->resultset("Artist")->count, 4, 'count ok');

# test find_or_new
{
  my $existing_obj = $schema->resultset('Artist')->find_or_new({
    artistid => 4,
  });

  is($existing_obj->name, 'Man With A Spoon', 'find_or_new: found existing artist');
  ok($existing_obj->in_storage, 'existing artist is in storage');

  my $new_obj = $schema->resultset('Artist')->find_or_new({
    artistid => 5,
    name     => 'find_or_new',
  });

  is($new_obj->name, 'find_or_new', 'find_or_new: instantiated a new artist');
  ok(! $new_obj->in_storage, 'new artist is not in storage');
}

my $cd = $schema->resultset("CD")->find(1);
my %cols = $cd->get_columns;

is(keys %cols, 6, 'get_columns number of columns ok');

is($cols{title}, 'Spoonful of bees', 'get_columns values ok');

%cols = ( title => 'Forkful of bees', year => 2005);
$cd->set_columns(\%cols);

is($cd->title, 'Forkful of bees', 'set_columns ok');

is($cd->year, 2005, 'set_columns ok');

$cd->discard_changes;

# check whether ResultSource->columns returns columns in order originally supplied
my @cd = $schema->source("CD")->columns;

is_deeply( \@cd, [qw/cdid artist title year genreid single_track/], 'column order');

$cd = $schema->resultset("CD")->search({ title => 'Spoonful of bees' }, { columns => ['title'] })->next;
is($cd->title, 'Spoonful of bees', 'subset of columns returned correctly');

$cd = $schema->resultset("CD")->search(undef, { include_columns => [ 'artist.name' ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('name'), 'Caterwauler McCrae', 'Additional column returned');

# check if new syntax +columns also works for this
$cd = $schema->resultset("CD")->search(undef, { '+columns' => [ 'artist.name' ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('name'), 'Caterwauler McCrae', 'Additional column returned');

# check if new syntax for +columns select specifiers works for this
$cd = $schema->resultset("CD")->search(undef, { '+columns' => [ {artist_name => 'artist.name'} ], join => [ 'artist' ] })->find(1);

is($cd->title, 'Spoonful of bees', 'Correct CD returned with include');
is($cd->get_column('artist_name'), 'Caterwauler McCrae', 'Additional column returned');

# update_or_insert
$new = $schema->resultset("Track")->new( {
  trackid => 100,
  cd => 1,
  title => 'Insert or Update',
  last_updated_on => '1973-07-19 12:01:02'
} );
$new->update_or_insert;
ok($new->in_storage, 'update_or_insert insert ok');

# test in update mode
$new->title('Insert or Update - updated');
$new->update_or_insert;
is( $schema->resultset("Track")->find(100)->title, 'Insert or Update - updated', 'update_or_insert update ok');

# get_inflated_columns w/relation and accessor alias
SKIP: {
    skip "This test requires DateTime::Format::MySQL", 8 if $NO_DTFM;

    isa_ok($new->updated_date, 'DateTime', 'have inflated object via accessor');
    my %tdata = $new->get_inflated_columns;
    is($tdata{'trackid'}, 100, 'got id');
    isa_ok($tdata{'cd'}, 'DBICTest::CD', 'cd is CD object');
    is($tdata{'cd'}->id, 1, 'cd object is id 1');
    is(
        $tdata{'position'},
        $schema->resultset ('Track')->search ({cd => 1})->count,
        'Ordered assigned proper position',
    );
    is($tdata{'title'}, 'Insert or Update - updated');
    is($tdata{'last_updated_on'}, '1973-07-19T12:01:02');
    isa_ok($tdata{'last_updated_on'}, 'DateTime', 'inflated accessored column');
}

eval { $schema->class("Track")->load_components('DoesNotExist'); };

ok $@, $@;

is($schema->class("Artist")->field_name_for->{name}, 'artist name', 'mk_classdata usage ok');

my $search = [ { 'tags.tag' => 'Cheesy' }, { 'tags.tag' => 'Blue' } ];

my( $or_rs ) = $schema->resultset("CD")->search_rs($search, { join => 'tags',
                                                  order_by => 'cdid' });
# At this point in the test there are:
# 1 artist with the cheesy AND blue tag
# 1 artist with the cheesy tag
# 2 artists with the blue tag
#
# Formerly this test expected 5 as there was no collapsing of the AND condition
is($or_rs->count, 4, 'Search with OR ok');

my $distinct_rs = $schema->resultset("CD")->search($search, { join => 'tags', distinct => 1 });
is($distinct_rs->all, 4, 'DISTINCT search with OR ok');

{
  my $tcount = $schema->resultset('Track')->search(
    {},
    {
      select => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
      columns => [ qw/position title/ ],
      distinct => 1,
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT ok');

  $tcount = $schema->resultset('Track')->search(
    {},
    {
       group_by => [ qw/position title/ ]
    }
  );
  is($tcount->count, 13, 'multiple column COUNT DISTINCT using column syntax ok');  
}

my $tag_rs = $schema->resultset('Tag')->search(
               [ { 'me.tag' => 'Cheesy' }, { 'me.tag' => 'Blue' } ]);

my $rel_rs = $tag_rs->search_related('cd');

# At this point in the test there are:
# 1 artist with the cheesy AND blue tag
# 1 artist with the cheesy tag
# 2 artists with the blue tag
#
# Formerly this test expected 5 as there was no collapsing of the AND condition
is($rel_rs->count, 4, 'Related search ok');

is($or_rs->next->cdid, $rel_rs->next->cdid, 'Related object ok');
$or_rs->reset;
$rel_rs->reset;

my $tag = $schema->resultset('Tag')->search(
               [ { 'me.tag' => 'Blue' } ], { cols=>[qw/tagid/] } )->next;

ok($tag->has_column_loaded('tagid'), 'Has tagid loaded');
ok(!$tag->has_column_loaded('tag'), 'Has not tag loaded');

ok($schema->storage(), 'Storage available');

{
  my $rs = $schema->resultset("Artist")->search({
    -and => [
      artistid => { '>=', 1 },
      artistid => { '<', 3 }
    ]
  });

  $rs->update({ name => 'Test _cond_for_update_delete' });

  my $art;

  $art = $schema->resultset("Artist")->find(1);
  is($art->name, 'Test _cond_for_update_delete', 'updated first artist name');

  $art = $schema->resultset("Artist")->find(2);
  is($art->name, 'Test _cond_for_update_delete', 'updated second artist name');
}

# test source_name
{
  # source_name should be set for normal modules
  is($schema->source('CD')->source_name, 'CD', 'source_name is set to moniker');

  # test the result source that sets source_name explictly
  ok($schema->source('SourceNameArtists'), 'SourceNameArtists result source exists');

  my @artsn = $schema->resultset('SourceNameArtists')->search({}, { order_by => 'name DESC' });
  is(@artsn, 4, "Four artists returned");
  
  # make sure subclasses that don't set source_name are ok
  ok($schema->source('ArtistSubclass'), 'ArtistSubclass exists');
}

my $newbook = $schema->resultset( 'Bookmark' )->find(1);

lives_ok (sub { my $newlink = $newbook->link}, "stringify to false value doesn't cause error");

# test cascade_delete through many_to_many relations
{
  my $art_del = $schema->resultset("Artist")->find({ artistid => 1 });
  lives_ok (sub { $art_del->delete }, 'Cascading delete on Ordered has_many works' );  # real test in ordered.t
  is( $schema->resultset("CD")->search({artist => 1}), 0, 'Cascading through has_many top level.');
  is( $schema->resultset("CD_to_Producer")->search({cd => 1}), 0, 'Cascading through has_many children.');
}

# test column_info
{
  $schema->source("Artist")->{_columns}{'artistid'} = {};
  $schema->source("Artist")->column_info_from_storage(1);

  my $typeinfo = $schema->source("Artist")->column_info('artistid');
  is($typeinfo->{data_type}, 'INTEGER', 'column_info ok');
  $schema->source("Artist")->column_info('artistid');
  ok($schema->source("Artist")->{_columns_info_loaded} == 1, 'Columns info flag set');
}

# test source_info
{
  my $expected = {
    "source_info_key_A" => "source_info_value_A",
    "source_info_key_B" => "source_info_value_B",
    "source_info_key_C" => "source_info_value_C",
  };

  my $sinfo = $schema->source("Artist")->source_info;

  is_deeply($sinfo, $expected, 'source_info data works');
}

# test remove_columns
{
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title year genreid single_track/],
    'initial columns',
  );

  $schema->source('CD')->remove_columns('coolyear'); #should not delete year
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title year genreid single_track/],
    'nothing removed when removing a non-existent column',
  );

  $schema->source('CD')->remove_columns('genreid', 'year');
  is_deeply(
    [$schema->source('CD')->columns],
    [qw/cdid artist title single_track/],
    'removed two columns',
  );

  my $priv_columns = $schema->source('CD')->_columns;
  ok(! exists $priv_columns->{'year'}, 'year purged from _columns');
  ok(! exists $priv_columns->{'genreid'}, 'genreid purged from _columns');
}

# test get_inflated_columns with objects
SKIP: {
    skip "This test requires DateTime::Format::MySQL", 5 if $NO_DTFM;
    my $event = $schema->resultset('Event')->search->first;
    my %edata = $event->get_inflated_columns;
    is($edata{'id'}, $event->id, 'got id');
    isa_ok($edata{'starts_at'}, 'DateTime', 'start_at is DateTime object');
    isa_ok($edata{'created_on'}, 'DateTime', 'create_on DateTime object');
    is($edata{'starts_at'}, $event->starts_at, 'got start date');
    is($edata{'created_on'}, $event->created_on, 'got created date');
}

# test resultsource->table return value when setting
{
    my $class = $schema->class('Event');
    my $table = $class->table($class->table);
    is($table, $class->table, '->table($table) returns $table');
}

#make sure insert doesn't use set_column
{
  my $en_row = $schema->resultset('Encoded')->new_result({encoded => 'wilma'});
  is($en_row->encoded, 'amliw', 'new encodes');
  $en_row->insert;
  is($en_row->encoded, 'amliw', 'insert does not encode again');
}
