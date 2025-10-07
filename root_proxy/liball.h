/*
    #################################################################
    #    (c) Copyright 2009-2025 JRCS Ltd  - All Rights Reserved    #
    #################################################################
*/
#ifndef _INCLUDE_LIBALL_H
#define _INCLUDE_LIBALL_H

#include <stdint.h>
#include <netinet/in.h>
#include "ipall.h"

typedef uint16_t word_t;
typedef uint8_t byte_t;

extern void *eolncpy(const char * file,const int line, char * dst, char * src,int size_of);
#define STRECAT(D,E,S)  eolncpy(__FILE__,__LINE__,(char *)D+strlen((char *)D),(char *)S,((char *)E-(char *)D))
#define STRECPY(D,E,S)  eolncpy(__FILE__,__LINE__,(char *)D,(char *)S,((char *)E-(char *)D))
#define STRNCPY(D,S,N)  eolncpy(__FILE__,__LINE__,D,S,N)
#define STRCPY(D,S)     eolncpy(__FILE__,__LINE__,D,S,sizeof(D))
#define STRCAT(D,S)     eolncpy(__FILE__,__LINE__,(char *)D+strlen((char *)D),S,sizeof(D)-strlen(D))
#define SEPRINTF(A,E,args...) snprintf((char *)A,((char *)E-(char *)A),## args)
#define SPRINTF(A,args...) snprintf((char *)A,sizeof(A),## args)

#define MEMCPY memmove

#define IPADDRCHAR(A) (((A).is_type==4)?ipchar((A).addr.v4):ip6char(&((A).addr.v6)))
#define IPCHAR(A) IPADDRCHAR(A)

#define BLANK(A) ((A==NULL)||(A[0]==0))
#define ZERO(A) memset(&A,0,sizeof(A))
#define AZERO(A) memset(A,0,sizeof(A))

extern char * ip6char(struct in6_addr * addr);
extern char * ipchar(in_addr_t addr);
extern int set_blocking(int fd,int blocking);
extern void mksin6(struct sockaddr_in6 *sin,struct in6_addr *addr, unsigned short port);
extern int decode_net_addr(struct net_addr_st *ni,char * addr_in);
extern uint64_t xtoi(char * hex);
extern int change_to_user(char * run_as);

#endif // _INCLUDE_LIBALL_H
