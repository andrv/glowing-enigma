#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: hello.pl
#
#        USAGE: morbo hello.pl  
#
#  DESCRIPTION: mojolicious start
#
#===============================================================================

use Mojolicious::Lite;
use Mojo::Asset::File;

my $config = plugin 'Config';

plugin 'TagHelpers';

get '/' => sub {
    my $c = shift;
    $c->render( template => 'index' );
};

get '/foo' => sub {
    my $c = shift;
    my $user = $c->param( 'user' ) || '';

    $c->render(
        template => 'index',
        moreContent => "Hello foo '$user' sombody!\nBye.\n",
    );
};

get '/showConfig' => sub {
    my $c = shift;

    my $file = Mojo::Asset::File->new( path => $config->{userNameFile} );
    my $gUserName = $file->slurp;
    
    $file = Mojo::Asset::File->new( path => $config->{devApiKey} );
    my $gApiKey = $file->slurp;

    $c->render(
        template  => 'showConfig',
        gUserName => $gUserName,
        gApiKey   => $gApiKey,
    );
};

get '/work' => sub {
    my $c = shift;

    $c->render(
        template => 'work',
        action   => '',
    );
};

get '/work/:action' => sub {
    my $c = shift;
    my $action = $c->stash( 'action' );

    if( $action eq 'fetch' ) {
        #
    }

    $c->render(
        template => 'work',
        action   => $action,
    );
};

app->start;
