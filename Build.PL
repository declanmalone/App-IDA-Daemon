use v5.10;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'App::IDA::Daemon',
    license             => 'perl,lgpl,artistic2',
    dist_author         => q{Declan Malone <idablack@users.sourceforge.net>},
    dist_version_from   => 'lib/App/IDA/Daemon.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
	'Mojolicious'       => 0,
	'Crypt::IDA'        => 0.03,
	# Old (~2.000006) Role::Tiny fails on +PullsFromUpstream
	'Role::Tiny'        => 2.001004,
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    add_to_cleanup     => [ 'App-IDA-Daemon-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
