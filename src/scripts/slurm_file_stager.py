#!/usr/bin/env python

#
# Simple HTTP-based service to stage files between the CEs and WNs
#

import os
import os.path
import stat
from BaseHTTPServer import BaseHTTPRequestHandler
from cgi import parse_multipart, parse_header
from urlparse import parse_qs
import urlparse

class StagerHandler(BaseHTTPRequestHandler):
    def check_auth(self):
        if self.client_address[0] == "127.0.0.1":
            return True
        elif self.client_address[0].startswith("10.0"):
            return True
        else:
            self.send_response(403)
            self.end_headers()
            self.wfile.write("This IP is not authorized: %s.\r\n" % self.client_address[0])
            return False

    def do_GET(self):
        if not self.check_auth():
            return
        parsed_path = self.path
        parsed_path = os.path.normpath(parsed_path)
        parsed_path = os.path.realpath(parsed_path)
        if not parsed_path.startswith('/var/lib/condor-ce/spool/'):
            print "Illegal path %s" % os.path.realpath(parsed_path)
            self.fail("PATH")
            return
        if not os.path.exists(parsed_path):
            print "404: %s" % parsed_path
            self.fail()
        else:
            self.send_response(200)
            self.end_headers()
            size = os.stat(parsed_path).st_size
            print "Sending %s (%s bytes)" % (parsed_path, size)
            self.wfile.write(open(parsed_path, "rb").read())

    def fail(self, msg="FAIL"):
        self.send_response(500)
        self.end_headers()
        self.wfile.write("%s\r\n" % msg)
        return

    def do_POST(self):
        if not self.check_auth():
            return
        parsed_path = self.path
        parsed_path = os.path.normpath(parsed_path)
        parsed_path = os.path.realpath(parsed_path)
        if not parsed_path.startswith('/var/lib/condor-ce/spool/'):
            print "Illegal path %s" % os.path.realpath(parsed_path)
            self.fail("PATH")
            return
        ctype, pdict = parse_header(self.headers['content-type'])
        if ctype == 'multipart/form-data':
            if int(self.headers['content-length']) > 1024*1024*20:
                # Don't accept files larger than 20MB
                print "Too large %s" % self.headers['content-length']
                self.fail()
                return

            postvars = parse_multipart(self.rfile, pdict)
        elif ctype == 'application/x-www-form-urlencoded':
            length = int(self.headers['content-length'])
            postvars = parse_qs(
                    self.rfile.read(length),
                    keep_blank_values=1)
        else:
            postvars = {}
        outdata = postvars['data'][0]
        try:
            parent_dir = os.path.dirname(parsed_path)
            if not os.path.exists(parent_dir):
                self.fail("PATH")
                return
            dirstat = os.stat(parent_dir)
            uid = dirstat.st_uid
            gid = dirstat.st_gid
            with open(parsed_path, 'wb') as fh:
                os.fchown(fh.fileno(), uid, gid)
                fh.write(outdata)
                fh.flush()
                os.fsync(fh.fileno())
            size = os.stat(parsed_path).st_size
            print "Received %s (%s bytes)" % (parsed_path, size)
        except IOError, e:
            print "ioerror: %s" % e
            self.fail("IO")
            return

        message = 'OK\r\n'
        self.send_response(200)
        self.end_headers()
        self.wfile.write(message)
        return


if __name__ == '__main__':
    from BaseHTTPServer import HTTPServer
    server = HTTPServer(('0.0.0.0', 8080), StagerHandler)
    print 'Starting server, use <Ctrl-C> to stop'
    server.serve_forever()

