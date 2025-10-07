/*
    #################################################################
    #    (c) Copyright 2009-2025 JRCS Ltd  - All Rights Reserved    #
    #################################################################
*/
#include <stdio.h>
#include <unistd.h>
#include <ctype.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/types.h>
#include <pwd.h>

#include "liball.h"
#include "log_message.h"


char * ipchar(in_addr_t addr)
{
struct in_addr ad;

    memset(&ad,0,sizeof(ad));
    ad.s_addr = addr;
    return inet_ntoa(ad);
}



char * ip6char(struct in6_addr * addr)
{
static char ip6[INET6_ADDRSTRLEN+10];

    inet_ntop(AF_INET6,addr,ip6,INET6_ADDRSTRLEN+5);
    return ip6;
}


void * eolncpy(const char * file,const int line, char * dst, char * src,int size_of)
{

    // logmsg(MSG_DEBUG_HIGH,"%s[%d]: Copying '%s', %d bytes -> %08X\n",file,line,src,size_of,dst);

    if (!src) { dst[0]=0; return dst; }
    int len = strlen(src);
    if (!len) { dst[0]=0; return dst; }

    if (len >= size_of) {
        logmsg(MSG_ERROR,"ERROR: %s[%d] - str/size_of exceeded (%ld >= %d)\n",file,line,len,size_of);
        len = size_of;
        }
    MEMCPY(dst,src,len);
    dst[len] = 0;
    return dst+len;
}




int set_blocking(int fd,int blocking)
{
int flags = fcntl(fd, F_GETFL);

    if (blocking) flags &= ~O_NONBLOCK; else flags |= O_NONBLOCK;
    return fcntl(fd,F_SETFL,flags);
}



void mksin6(struct sockaddr_in6 *sin,struct in6_addr *addr, word_t port)
{
    memset(sin,0,sizeof(struct sockaddr_in6));
    sin->sin6_family = AF_INET6;
    sin->sin6_port = htons(port);
    MEMCPY(&sin->sin6_addr,addr,sizeof(struct in6_addr));
}



int decode_net_addr(struct net_addr_st *ni,char * addr_in)
{
char addr[50],*a;
int d=0,c=0;

    logmsg(MSG_DEBUG,"decode_net_addr '%s'\n",addr_in);
    memset(ni,0,sizeof(struct net_addr_st));
    if (BLANK(addr_in)) return -1;

    STRCPY(addr,addr_in);
    for(a=addr;*a;a++) { if (*a=='.') d++; if (*a==':') c++; }

    if (d>c) {
        if ((a = strchr(addr,':'))!=NULL) { *a=0; a++; }
        if (inet_pton(AF_INET,addr,&ni->addr.v4) == 1) {
            logmsg(MSG_DEBUG,"decode_net_addr IPv4=%s\n",ipchar(ni->addr.v4));
            if (a) ni->port = atoi(a);
            ni->is_type=4; return 0; }
    }
    else if (c>d) {
        if ((a = strchr(addr,'.'))!=NULL) { *a=0; a++; }
        if (inet_pton(AF_INET6,addr,&ni->addr.v6) == 1) {
            logmsg(MSG_DEBUG,"decode_net_addr IPv6=%s\n",ip6char(&ni->addr.v6));
            if (a) ni->port = atoi(a);
            ni->is_type=6; return 0; }
        }
    return -1;
}



uint8_t hexchar(char ch)
{
    if (ch>='a') ch = toupper(ch);
    if (ch > '9') return (ch - 'A' + 10); else return ch - '0';
}



uint64_t xtoi(char * hex)
{
uint64_t x = 0;
char * cp;

    for(cp=hex;*cp;cp++) x = (x << 4) + hexchar(*cp);
    return x;
}



int change_to_user(char * run_as)
{
char buf[1000];
struct passwd psent,*pp;

    if ((getpwnam_r(run_as,&psent,buf,sizeof(buf),&pp))) {
        logmsg(MSG_ERROR,"ERROR: Can't id user '%s' (%s)\n",run_as,ERRMSG);
        return -9; }

    if (setgid(psent.pw_gid)) {
        logmsg(MSG_ERROR,"Failed to change to GID %d (%s)\n",psent.pw_gid,ERRMSG);
        return -1; }

    if (setuid(psent.pw_uid)) {
        logmsg(MSG_ERROR,"Failed to change to UID %d (%s)\n",psent.pw_uid,ERRMSG);
        return -2; }

    return 0;
}
