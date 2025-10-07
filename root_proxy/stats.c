#include <stdio.h>

#include "stats.h"
#include "log_message.h"

void stats_add(struct stats_count_st *c,int sz)
{
    if (sz < 0) return;
    c->count++;
    c->bytes += sz;
}



void stats_add_count(struct stats_count_st * total,struct stats_count_st *thread_stats)
{
    total->count += thread_stats->count;
    total->bytes += thread_stats->bytes;
}



void stats_add_channel(struct stats_channel_st * total,struct stats_channel_st *thread_stats)
{
    stats_add_count(&total->qry,&thread_stats->qry);
    stats_add_count(&total->resp,&thread_stats->resp);
}



void stats_add_to_total(struct stats_st * total,struct stats_st *thread_stats)
{
    stats_add_channel(&total->client,&thread_stats->client);
    stats_add_channel(&total->first,&thread_stats->first);
    stats_add_channel(&total->second,&thread_stats->second);
}




void stats_channel(FILE *prom_fp, char *who,struct stats_channel_st *ch)
{
    logmsg(MSG_HIGH,"%10s: QRY %ld pkts, %ld bytes - RESP %ld pkts, %ld bytes\n",
        who,ch->qry.count,ch->qry.bytes,ch->resp.count,ch->resp.bytes);
    if (!prom_fp) return;
    fprintf(prom_fp,"root_proxy_%s_query_count %ld\n",who,ch->qry.count);
    fprintf(prom_fp,"root_proxy_%s_query_bytes %ld\n",who,ch->qry.bytes);
    fprintf(prom_fp,"root_proxy_%s_response_count %ld\n",who,ch->resp.count);
    fprintf(prom_fp,"root_proxy_%s_response_bytes %ld\n",who,ch->resp.bytes);
}


void stats_write_to_file(char *prom_file,struct stats_st *stats)
{
FILE *prom_fp = NULL;

    if (!prom_file[0]) return;

    if ((prom_fp = fopen(prom_file,"w+")) == NULL) {
    	logmsg(MSG_ERROR,"ERROR: Failed to write prom file '%s' - %s\n",prom_file,ERRMSG);
    	return; }

    stats_channel(prom_fp,"client",&stats->client);
    stats_channel(prom_fp,"first",&stats->first);
    stats_channel(prom_fp,"second",&stats->second);
    fclose(prom_fp);
}
