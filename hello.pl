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
use Mojo::UserAgent;
use Mojo::JSON qw( decode_json encode_json );

use Data::Dumper;

my $config = plugin 'Config';

plugin 'TagHelpers';

my $file = Mojo::Asset::File->new( path => $config->{appSecrets} );
my $appSecrets = decode_json( $file->slurp )->{web};

plugin 'OAuth2' => {
    google => {
        key    => $appSecrets->{client_id},
        secret => $appSecrets->{client_secret},
    }
};

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

    $c->render(
        template   => 'showConfig',
        appSecrets => $appSecrets,
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

    my $res;

    if( $action eq 'check' ) {
        my @scopes = qw(
            https://mail.google.com/
            https://www.googleapis.com/auth/gmail.modify
            https://www.googleapis.com/auth/gmail.readonly
        );

        if( my $err = $c->param( 'error' ) ) {
            print Dumper $err;
        }
        elsif( my $data = $c->oauth2->get_token( 'google' => { scope => join ' ', @scopes } ) ) {
            my $accessTokenUrlPart = "access_token=$data->{access_token}";

            my $url = 'https://www.googleapis.com/gmail/v1/users/me'.
                      '/messages?q=from:kueche@kabi-kamenz.de has:attachment is:unread&'.
                      $accessTokenUrlPart;

            my $ua = Mojo::UserAgent->new;
            $res = $ua->get( $url )->res->json;

            $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$res->{messages}->[0]->{id}?$accessTokenUrlPart";
            $res = $ua->get( $url )->res->json;

            foreach my $header( @{$res->{payload}->{headers}} ) {
                $c->stash( subj => $header->{value} ) if $header->{name} eq 'Subject';
            }

            my $attachments = [];
            foreach my $messagePart( @{$res->{payload}->{parts}} ) {
                push(
                    @$attachments, {
                        filename => $messagePart->{filename},
                        id => $messagePart->{body}->{attachmentId},
                    }
                ) if $messagePart->{filename};
            }
            $c->stash( attachments => $attachments );
        }
        else {
            return;
        }
    }

    $c->render(
        template => 'workaction',
        action   => $action,
        res    => $res,
    );
};

app->start;
