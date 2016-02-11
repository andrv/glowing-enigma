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

my @scopes = qw(
    https://mail.google.com/
    https://www.googleapis.com/auth/gmail.modify
    https://www.googleapis.com/auth/gmail.readonly
);

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

get '/work/check' => sub {
    my $c = shift;

    my $res;

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

        my $messagesFound = $res->{resultSizeEstimate} ? 1 : 0;
        $c->stash( messagesFound => $messagesFound );

        my $messageData = [];

        foreach my $message( @{$res->{messages}} ) {
            my $metadata = { id => $message->{id} };

            $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message->{id}?$accessTokenUrlPart";
            my $res = $ua->get( $url )->res->json;

            foreach my $header( @{$res->{payload}->{headers}} ) {
                $metadata->{subj} = $header->{value} if $header->{name} eq 'Subject';
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

            $metadata->{attachments} = $attachments;

            push @$messageData, $metadata;
        }
        $c->stash( messages => $messageData );
    }
    else {
        return;
    }

    $c->render(
        template => 'checking',
    );
};

get '/work/fetch' => sub {
    my $c            = shift;
    my $messageId    = $c->param( 'mess' );
    my $attachmentId = $c->param( 'attach' );

    my $file = Mojo::Asset::File->new;
    $file->add_chunk( 'some data' );
    $file->move_to( 'some.data' );

    my $res;

    if( my $err = $c->param( 'error' ) ) {
        print Dumper $err;
    }
    elsif( my $data = $c->oauth2->get_token( 'google' => { scope => join ' ', @scopes } ) ) {
        my $accessTokenUrlPart = "access_token=$data->{access_token}";

        my $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$messageId/attachments/$attachmentId?$accessTokenUrlPart";

#        my $ua = Mojo::UserAgent->new;
#        $res = $ua->get( $url )->res->json;

        my $file = Mojo::Asset::File->new;
        $file->add_chunk( 'some data' );
#            {
#                "attachmentId": string,
#                "size": integer,
#                "data": bytes
#            }
    }
    else {
        return;
    }

    $c->render(
        template => 'fetching',
    );
};

app->start;
