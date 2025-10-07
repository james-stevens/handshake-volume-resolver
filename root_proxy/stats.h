/*
    #################################################################
    #    (c) Copyright 2009-2025 JRCS Ltd  - All Rights Reserved    #
    #################################################################
*/
#ifndef _INCLUDE_STATS_H_
#define _INCLUDE_STATS_H_

#include <stdio.h>
#include <stdint.h>

struct stats_count_st { uint64_t count,bytes; };
struct stats_channel_st { struct stats_count_st qry,resp; };
struct stats_st { struct stats_channel_st client,first,second; };

extern void stats_add(struct stats_count_st *c,int sz);
extern void stats_add_to_total(struct stats_st * total,struct stats_st *thread_stats);
extern void stats_write_to_file(char *prom_file,struct stats_st *stats);

#endif // _INCLUDE_STATS_H_
