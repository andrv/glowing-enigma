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
use Mojo::Util qw( spurt encode );
use MIME::Base64::URLSafe;
use Mojo::DOM;
use File::Spec;

use lib 'lib';
use Html;

use Data::Dumper;

my $config       = plugin 'Config';
my $sourceDir    = $config->{sourceDir};
my $convertedDir = $config->{converted};

plugin 'TagHelpers';

my $file = Mojo::Asset::File->new( path => $config->{appSecrets} );
my $appSecrets = decode_json( $file->slurp )->{web};

$file = Mojo::Asset::File->new( path => File::Spec->catfile( $config->{searchDir}, $config->{search} ) );
my $search = $file->slurp;

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

my $localStore = {};

my $h = Html->new;

my $nav = $h->div( name => 'nav',
    $h->ul([
            $h->link( to => '/',           'Home' ),
            $h->link( to => '/list',       'Working on the file' ),
            $h->link( to => '/showConfig', 'Show configuration' ),
    ])
);

sub out {
    my $content = shift || '';
    return $nav. $content;
}

get '/' => sub {
    my $c = shift;
    my $h = Html->new;

    $c->render( data => $h->html( 'The beginn..', out() ) );
};

get '/showConfig' => sub {
    my $c = shift;

    $c->render( data => $h->html( 'Show configuration', out(
                $h->h5( 'Configuration:' ).
                $h->ul([
                        "App secrets location: $config->{appSecrets}",
                        '-----',
                        "Google app secrets: ". Dumper( $appSecrets ),
                ])
            ))
    );
};

get '/list' => sub {
    my $c = shift;
    my $foundLocalFiles = checkLocalFiles();

    my $localFilesList = '';

    if( %$foundLocalFiles ) {
        $localFilesList = "or process local files:";
        foreach my $dir( keys %$foundLocalFiles ) {
            my @files;

            foreach my $file( @{$foundLocalFiles->{$dir}} ) {
                $file = $h->link( to => "/convert/$file", $file ) if $dir eq $sourceDir;
                $file = $h->link( to => "/parse/$file", $file ) if $dir eq $convertedDir;
                push @files, $file;
            }

            $localFilesList .= $h->ul([
                    "$dir:".
                    $h->ul([ @files ]),
                ])
        }
    }

    $c->render( data => $h->html( 'Processing files',
            out(
                $h->h5( 'Working on the files' ).
                "Check for".
                $h->ul([ $h->link( to => '/check', 'mail' ) ]).
                $localFilesList
            ))
    );
};

sub checkLocalFiles {
    my $files = {};

    foreach my $dir( $sourceDir, $convertedDir ) {
        opendir( my $dh, $dir ) or die "can't opendir $dir $!";

        while( my $file = readdir $dh ) {
            next unless -f File::Spec->catfile( $dir, $file );
            next unless $file =~ m/\.\w+$/;
            push @{$files->{$dir}}, $file;
        }

        closedir $dh;
    }

    return $files;
}

get '/check' => sub {
    my $c = shift;

    my $res;

    my $messageData = [];

    if( my $err = $c->param( 'error' ) ) {
        print Dumper $err;
    }
    elsif( my $data = $c->oauth2->get_token( 'google' => { scope => join ' ', @scopes } ) ) {
        $localStore->{accessTokenUrlPart} = "access_token=$data->{access_token}";

        my $url = 'https://www.googleapis.com/gmail/v1/users/me'.
                  "/messages?q=$search&".
                  $localStore->{accessTokenUrlPart};

        my $ua = Mojo::UserAgent->new;
        $res = $ua->get( $url )->res->json;

        foreach my $message( @{$res->{messages}} ) {
            my $metadata = { id => $message->{id} };

            $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message->{id}?$localStore->{accessTokenUrlPart}";
            my $res = $ua->get( $url )->res->json;

            foreach my $header( @{$res->{payload}->{headers}} ) {
                $metadata->{subj} = encode( 'UTF-8', $header->{value} ) if $header->{name} eq 'Subject';
            }

            my @attachments;
            foreach my $messagePart( @{$res->{payload}->{parts}} ) {
                if( $messagePart->{filename} ) {
                    my $filename = encode( 'UTF-8', $messagePart->{filename} );
                    my $show = $h->link(
                        to => "/fetch/$message->{id}/$messagePart->{body}{attachmentId}/$filename",
                        $filename
                    ) if $messagePart->{filename} =~ m/jpg$|png$|doc$|pdf$/;
                    $show //= $filename;

                    push @attachments, $show;
                }
            }

            $metadata->{attachments} = [ @attachments ];

            push @$messageData, $metadata;
        }
    }
    else {
        return;
    }

    my $mails = @$messageData ? 'New mails:' : 'No new mails, try again later';
    foreach my $message ( @$messageData ) {
        $mails .= $h->ul([ $message->{subj}. $h->ul( $message->{attachments} ) ])
    }

    $c->render( data => $h->html( 'Processing files - mails found',
            out(
                $h->h5( 'Checked mails' ).
                $mails
            ))
    );
};

get '/fetch/:message/:attachment/#name' => sub {
    my $c          = shift;
    my $message    = $c->stash( 'message' );
    my $attachment = $c->stash( 'attachment' );

    my $url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message/attachments/$attachment?$localStore->{accessTokenUrlPart}";

    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get( $url )->res->json;

    my $bytes = encode 'UTF-8', $res->{data};
    $bytes = urlsafe_b64decode $bytes;

    my $path = File::Spec->catfile( $sourceDir, $c->stash( 'name' ) );

    spurt $bytes, $path;

    $c->redirect_to( '/list' );
};

get '/convert/#name' => sub {
    my $c    = shift;
    my $name = $c->stash( 'name' );

    my $sourcePath = File::Spec->catfile( $sourceDir, $name );
    my $converter = qq(libreoffice --convert-to "html:XHTML Writer File:UTF8" --outdir $convertedDir '$sourcePath');
    system $converter;

    $name =~ s/doc/html/;
    my $targetPath = File::Spec->catfile( $convertedDir, $name );
    my $file = Mojo::Asset::File->new( path => encode( 'UTF-8', $targetPath ) );

    my $dom = Mojo::DOM->new( $file->slurp );

    say $dom->at( 'title' )->all_text;

    $c->render( inline => "Trying parse file: $name\n" );
};

app->start;
