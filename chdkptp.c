/* chdkptp.c
 *
 * based on ptpcam.c
 * Copyright (C) 2001-2005 Mariusz Woloszyn <emsi@ipartners.pl>
 * additions
 * Copyright (C) 2010-2011 <reyalp (at) gmail dot com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "config.h"
#include "ptp.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <utime.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <fcntl.h>
#ifndef WIN32
#include <sys/mman.h>
#endif
#include <usb.h>

#ifdef WIN32
#define usleep(usec) Sleep((usec)/1000)
#define sleep(sec) Sleep(sec*1000)
#endif

#ifdef ENABLE_NLS
#  include <libintl.h>
#  undef _
#  define _(String) dgettext (GETTEXT_PACKAGE, String)
#  ifdef gettext_noop
#    define N_(String) gettext_noop (String)
#  else
#    define N_(String) (String)
#  endif
#else
#  define textdomain(String) (String)
#  define gettext(String) (String)
#  define dgettext(Domain,Message) (Message)
#  define dcgettext(Domain,Message,Type) (Message)
#  define bindtextdomain(Domain,Directory) (Domain)
#  define _(String) (String)
#  define N_(String) (String)
#endif

#include "ptpcam.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#ifdef CHDKPTP_IUP
#include <iup.h>
#include <iuplua.h>
#ifdef CHDKPTP_CD
#include <cd.h>
#include <cdlua.h>
#include <cdiup.h>
#include <cdluaiup.h>
#endif
#endif
#include "lfs/lfs.h"
#include "lbuf.h"
#include "liveimg.h"
#include "rawimg.h"

/* some defines comes here */

/* CHDK additions */
#define CHDKPTP_VERSION_MAJOR 0
#define CHDKPTP_VERSION_MINOR 3

/* lua registry indexes */
/* meta table for connection objects */
#define CHDK_CONNECTION_META "chkdptp.connection_meta"
/* list of opened connections, indexed weakly as t[path] = connection */
#define CHDK_CONNECTION_LIST "chkdptp.connection_list"
/* meta table for for connection list */
#define CHDK_CONNECTION_LIST_META "chkdptp.connection_list_meta"

#define MAXCONNRETRIES 10


/* USB interface class */
#ifndef USB_CLASS_PTP
#define USB_CLASS_PTP		6
#endif

/* USB control message data phase direction */
#ifndef USB_DP_HTD
#define USB_DP_HTD		(0x00 << 7)	/* host to device */
#endif
#ifndef USB_DP_DTH
#define USB_DP_DTH		(0x01 << 7)	/* device to host */
#endif

/* PTP class specific requests */
#ifndef USB_REQ_DEVICE_RESET
#define USB_REQ_DEVICE_RESET		0x66
#endif
#ifndef USB_REQ_GET_DEVICE_STATUS
#define USB_REQ_GET_DEVICE_STATUS	0x67
#endif

/* USB Feature selector HALT */
#ifndef USB_FEATURE_HALT
#define USB_FEATURE_HALT	0x00
#endif

/* OUR APPLICATION USB URB (2MB) ;) */
#define PTPCAM_USB_URB		2097152

#define USB_TIMEOUT		5000

/* one global variable (yes, I know it sucks) */
short verbose=0;
/* the other one, it sucks definitely ;) */
// TODO this will go in the connection object
int ptpcam_usb_timeout = USB_TIMEOUT;

// TODO this is lame
#define CHDK_CONNECTION_METHOD PTPParams *params; PTP_USB *ptp_usb; get_connection_data(L,1,&params,&ptp_usb);

/* we need it for a proper signal handling :/ */
// reyalp -not using signal handler for now, revisit later
#if 0
PTPParams* globalparams;

void
ptpcam_siginthandler(int signum)
{
    PTP_USB* ptp_usb=(PTP_USB *)globalparams->data;
    struct usb_device *dev=usb_device(ptp_usb->handle);

    if (signum==SIGINT)
    {
	/* hey it's not that easy though... but at least we can try! */
	printf("Got SIGINT, trying to clean up and close...\n");
	usleep(5000);
	close_camera (ptp_usb, globalparams, dev);
	exit (-1);
    }
}
#endif

static short
ptp_read_func (unsigned char *bytes, unsigned int size, void *data)
{
	int result=-1;
	PTP_USB *ptp_usb=(PTP_USB *)data;
	int toread=0;
	signed long int rbytes=size;

	do {
		bytes+=toread;
		if (rbytes>PTPCAM_USB_URB) 
			toread = PTPCAM_USB_URB;
		else
			toread = rbytes;
		result=USB_BULK_READ(ptp_usb->handle, ptp_usb->inep,(char *)bytes, toread,ptpcam_usb_timeout);
		/* sometimes retry might help */
		if (result==0)
			result=USB_BULK_READ(ptp_usb->handle, ptp_usb->inep,(char *)bytes, toread,ptpcam_usb_timeout);
		if (result < 0)
			break;
		ptp_usb->read_count += toread;
		rbytes-=PTPCAM_USB_URB;
	} while (rbytes>0);

	if (result >= 0) {
		return (PTP_RC_OK);
	}
	else 
	{
		if (verbose) perror("usb_bulk_read");
		return PTP_ERROR_IO;
	}
}

static short
ptp_write_func (unsigned char *bytes, unsigned int size, void *data)
{
	int result;
	PTP_USB *ptp_usb=(PTP_USB *)data;

	result=USB_BULK_WRITE(ptp_usb->handle,ptp_usb->outep,(char *)bytes,size,ptpcam_usb_timeout);
	if (result >= 0) {
		ptp_usb->write_count += size;
		return (PTP_RC_OK);
	} else {
		if (verbose) perror("usb_bulk_write");
		return PTP_ERROR_IO;
	}
}

/* XXX this one is suposed to return the number of bytes read!!! */
static short
ptp_check_int (unsigned char *bytes, unsigned int size, void *data)
{
	int result;
	PTP_USB *ptp_usb=(PTP_USB *)data;

	result=USB_BULK_READ(ptp_usb->handle, ptp_usb->intep,(char *)bytes,size,ptpcam_usb_timeout);
	if (result==0)
	    result=USB_BULK_READ(ptp_usb->handle, ptp_usb->intep,(char *)bytes,size,ptpcam_usb_timeout);
	if (verbose>2) fprintf (stderr, "USB_BULK_READ returned %i, size=%i\n", result, size);

	if (result >= 0) {
		return result;
	} else {
		if (verbose) perror("ptp_check_int");
		return result;
	}
}


void
ptpcam_debug (void *data, const char *format, va_list args);
void
ptpcam_debug (void *data, const char *format, va_list args)
{
	if (verbose<2) return;
	vfprintf (stderr, format, args);
	fprintf (stderr,"\n");
	fflush(stderr);
}

void
ptpcam_error (void *data, const char *format, va_list args);
void
ptpcam_error (void *data, const char *format, va_list args)
{
/*	if (!verbose) return; */
	vfprintf (stderr, format, args);
	fprintf (stderr,"\n");
	fflush(stderr);
}



int
init_ptp_usb (PTPParams* params, PTP_USB* ptp_usb, struct usb_device* dev)
{
	usb_dev_handle *device_handle;

	params->write_func=ptp_write_func;
	params->read_func=ptp_read_func;
	params->check_int_func=ptp_check_int;
	params->check_int_fast_func=ptp_check_int;
	params->error_func=ptpcam_error;
	params->debug_func=ptpcam_debug;
	params->sendreq_func=ptp_usb_sendreq;
	params->senddata_func=ptp_usb_senddata;
	params->getresp_func=ptp_usb_getresp;
	params->getdata_func=ptp_usb_getdata;
	params->data=ptp_usb;
	params->transaction_id=0;
	params->byteorder = PTP_DL_LE;

	device_handle = usb_open(dev);
	if (!device_handle) {
		perror("usb_open()");
		return 0;
	}
	ptp_usb->handle=device_handle;
	ptp_usb->write_count = ptp_usb->read_count = 0;
	usb_set_configuration(device_handle, dev->config->bConfigurationValue);
	usb_claim_interface(device_handle,
		dev->config->interface->altsetting->bInterfaceNumber);
	// Get max endpoint packet size for bulk transfer fix
	params->max_packet_size = dev->config->interface->altsetting->endpoint->wMaxPacketSize;
//		fprintf(stderr,"max endpoint size = %d\n",params->max_packet_size);
	if (params->max_packet_size == 0) params->max_packet_size = 512;    // safety net ?
	return 1;
}

void
clear_stall(PTP_USB* ptp_usb)
{
	uint16_t status=0;
	int ret;

	/* check the inep status */
	ret=usb_get_endpoint_status(ptp_usb,ptp_usb->inep,&status);
	if (ret<0) perror ("inep: usb_get_endpoint_status()");
	/* and clear the HALT condition if happend */
	else if (status) {
		printf("Resetting input pipe!\n");
		ret=usb_clear_stall_feature(ptp_usb,ptp_usb->inep);
        	/*usb_clear_halt(ptp_usb->handle,ptp_usb->inep); */
		if (ret<0)perror ("usb_clear_stall_feature()");
	}
	status=0;

	/* check the outep status */
	ret=usb_get_endpoint_status(ptp_usb,ptp_usb->outep,&status);
	if (ret<0) perror ("outep: usb_get_endpoint_status()");
	/* and clear the HALT condition if happend */
	else if (status) {
		printf("Resetting output pipe!\n");
        	ret=usb_clear_stall_feature(ptp_usb,ptp_usb->outep);
		/*usb_clear_halt(ptp_usb->handle,ptp_usb->outep); */
		if (ret<0)perror ("usb_clear_stall_feature()");
	}

        /*usb_clear_halt(ptp_usb->handle,ptp_usb->intep); */
}

void
close_usb(PTP_USB* ptp_usb, struct usb_device* dev)
{
	//clear_stall(ptp_usb);
   	usb_release_interface(ptp_usb->handle, dev->config->interface->altsetting->bInterfaceNumber);
	usb_reset(ptp_usb->handle);
	usb_close(ptp_usb->handle);
}


struct usb_bus*
get_busses()
{
//	usb_init();
	usb_find_busses();
	usb_find_devices();
	return (usb_get_busses());
}

void
find_endpoints(struct usb_device *dev, int* inep, int* outep, int* intep);
void
find_endpoints(struct usb_device *dev, int* inep, int* outep, int* intep)
{
	int i,n;
	struct usb_endpoint_descriptor *ep;

	ep = dev->config->interface->altsetting->endpoint;
	n=dev->config->interface->altsetting->bNumEndpoints;

	for (i=0;i<n;i++) {
	if (ep[i].bmAttributes==USB_ENDPOINT_TYPE_BULK)	{
		if ((ep[i].bEndpointAddress&USB_ENDPOINT_DIR_MASK)==USB_ENDPOINT_DIR_MASK)
		{
			*inep=ep[i].bEndpointAddress;
			if (verbose>1)
				fprintf(stderr, "Found inep: 0x%02x\n",*inep);
		}
		if ((ep[i].bEndpointAddress&USB_ENDPOINT_DIR_MASK)==0)
		{
			*outep=ep[i].bEndpointAddress;
			if (verbose>1)
				fprintf(stderr, "Found outep: 0x%02x\n",*outep);
		}
		} else if ((ep[i].bmAttributes==USB_ENDPOINT_TYPE_INTERRUPT) &&
			((ep[i].bEndpointAddress&USB_ENDPOINT_DIR_MASK)==
				USB_ENDPOINT_DIR_MASK))
		{
			*intep=ep[i].bEndpointAddress;
			if (verbose>1)
				fprintf(stderr, "Found intep: 0x%02x\n",*intep);
		}
	}
}

void
close_camera(PTP_USB *ptp_usb, PTPParams *params)
{
	// usb_device(handle) appears to give bogus results when the device has gone away
	// TODO possible a different device could come back on this bus/dev ?
	struct usb_device *dev=find_device_by_path(ptp_usb->bus,ptp_usb->dev);
	if(!dev) {
		fprintf(stderr,"attempted to close non-present device %s:%s\n",ptp_usb->bus,ptp_usb->dev);
		return;
	}

	if (ptp_closesession(params)!=PTP_RC_OK)
		fprintf(stderr,"ERROR: Could not close session!\n");
	close_usb(ptp_usb, dev);
}

int
usb_get_endpoint_status(PTP_USB* ptp_usb, int ep, uint16_t* status)
{
	 return (usb_control_msg(ptp_usb->handle,
		USB_DP_DTH|USB_RECIP_ENDPOINT, USB_REQ_GET_STATUS,
		USB_FEATURE_HALT, ep, (char *)status, 2, 3000));
}

int
usb_clear_stall_feature(PTP_USB* ptp_usb, int ep)
{
	return (usb_control_msg(ptp_usb->handle,
		USB_RECIP_ENDPOINT, USB_REQ_CLEAR_FEATURE, USB_FEATURE_HALT,
		ep, NULL, 0, 3000));
}

int
usb_ptp_get_device_status(PTP_USB* ptp_usb, uint16_t* devstatus);
int
usb_ptp_get_device_status(PTP_USB* ptp_usb, uint16_t* devstatus)
{
	return (usb_control_msg(ptp_usb->handle,
		USB_DP_DTH|USB_TYPE_CLASS|USB_RECIP_INTERFACE,
		USB_REQ_GET_DEVICE_STATUS, 0, 0,
		(char *)devstatus, 4, 3000));
}

int
usb_ptp_device_reset(PTP_USB* ptp_usb);
int
usb_ptp_device_reset(PTP_USB* ptp_usb)
{
	return (usb_control_msg(ptp_usb->handle,
		USB_TYPE_CLASS|USB_RECIP_INTERFACE,
		USB_REQ_DEVICE_RESET, 0, 0, NULL, 0, 3000));
}

void
reset_device (struct usb_device *dev);
void
reset_device (struct usb_device *dev)
{
	PTPParams params;
	PTP_USB ptp_usb;
	uint16_t status;
	uint16_t devstatus[2] = {0,0};
	int ret;

	printf("reset_device: ");

	if (dev==NULL) {
		printf("null dev\n");
		return;
	}
	printf("dev %s\tbus %s\n",dev->filename,dev->bus->dirname);

	find_endpoints(dev,&ptp_usb.inep,&ptp_usb.outep,&ptp_usb.intep);

	if(!init_ptp_usb(&params, &ptp_usb, dev)) {
		printf("init_ptp_usb failed\n");
		return;
	}
	
	/* get device status (devices likes that regardless of its result)*/
	usb_ptp_get_device_status(&ptp_usb,devstatus);
	
	/* check the in endpoint status*/
	ret = usb_get_endpoint_status(&ptp_usb,ptp_usb.inep,&status);
	if (ret<0) perror ("usb_get_endpoint_status()");
	/* and clear the HALT condition if happend*/
	if (status) {
		printf("Resetting input pipe!\n");
		ret=usb_clear_stall_feature(&ptp_usb,ptp_usb.inep);
		if (ret<0)perror ("usb_clear_stall_feature()");
	}
	status=0;
	/* check the out endpoint status*/
	ret = usb_get_endpoint_status(&ptp_usb,ptp_usb.outep,&status);
	if (ret<0) perror ("usb_get_endpoint_status()");
	/* and clear the HALT condition if happend*/
	if (status) {
		printf("Resetting output pipe!\n");
		ret=usb_clear_stall_feature(&ptp_usb,ptp_usb.outep);
		if (ret<0)perror ("usb_clear_stall_feature()");
	}
	status=0;
	/* check the interrupt endpoint status*/
	ret = usb_get_endpoint_status(&ptp_usb,ptp_usb.intep,&status);
	if (ret<0)perror ("usb_get_endpoint_status()");
	/* and clear the HALT condition if happend*/
	if (status) {
		printf ("Resetting interrupt pipe!\n");
		ret=usb_clear_stall_feature(&ptp_usb,ptp_usb.intep);
		if (ret<0)perror ("usb_clear_stall_feature()");
	}

	/* get device status (now there should be some results)*/
	ret = usb_ptp_get_device_status(&ptp_usb,devstatus);
	if (ret<0) 
		perror ("usb_ptp_get_device_status()");
	else	{
		if (devstatus[1]==PTP_RC_OK) 
			printf ("Device status OK\n");
		else
			printf ("Device status 0x%04x\n",devstatus[1]);
	}
	
	/* finally reset the device (that clears prevoiusly opened sessions)*/
	ret = usb_ptp_device_reset(&ptp_usb);
	if (ret<0)perror ("usb_ptp_device_reset()");
	/* get device status (devices likes that regardless of its result)*/
	usb_ptp_get_device_status(&ptp_usb,devstatus);

	close_usb(&ptp_usb, dev);
}

//----------------------------
/*
get pointers out of user data in given arg
*/
static void get_connection_data(lua_State *L,int narg, PTPParams **params,PTP_USB **ptp_usb) {
	*params = (PTPParams *)luaL_checkudata(L,narg,CHDK_CONNECTION_META);
	*ptp_usb = (PTP_USB *)((*params)->data);
}

static void close_connection(PTPParams *params,PTP_USB *ptp_usb)
{
	if(ptp_usb->connected) {
		close_camera(ptp_usb,params);
	}
	ptp_usb->connected = 0;
}

static int check_connection_status(PTP_USB *ptp_usb) {
	uint16_t devstatus[2] = {0,0};
	
	if(!ptp_usb->connected) {// never initialized
		return 0;
	}
	if(usb_ptp_get_device_status(ptp_usb,devstatus) < 0) {
		return 0;
	}
	return (devstatus[1] == 0x2001);
}


/*
convenience - values extracted from a devinfo table
*/
typedef struct {
	const char *bus;
	const char *dev;
	unsigned vendor_id; // these are shorts in USB, but we want to allow special values
	unsigned product_id;
} devinfo_lua;
#define DEVINFO_LUA_ID_NONE 0x10000
/*
read lua devinfo table into C values
TODO this will go away, just use dev/bus, let lua deal with product id / vendor id if needed
*/
static int get_lua_devinfo(lua_State *L, int index, devinfo_lua *devinfo) {
	if(!devinfo) {
		return 0;
	}
	if(!lua_istable(L,index)) {
		// TODO HACKY - returns a blank devinfo if not table 
		devinfo->dev = devinfo->bus = NULL;
		devinfo->vendor_id = devinfo->product_id = DEVINFO_LUA_ID_NONE;
		return 0;
	}
	// TODO throw an error ? allow wildcards ?
	lua_getfield(L,index,"dev");
	devinfo->dev = lua_tostring(L,-1);
	lua_pop(L,1);

	lua_getfield(L,index,"bus");
	devinfo->bus = lua_tostring(L,-1);
	lua_pop(L,1);

	lua_getfield(L,index,"vendor_id");
	devinfo->vendor_id = luaL_optnumber(L,-1,DEVINFO_LUA_ID_NONE);
	lua_pop(L,1);

	lua_getfield(L,index,"product_id");
	devinfo->product_id = luaL_optnumber(L,-1,DEVINFO_LUA_ID_NONE);
	lua_pop(L,1);
	return 1;
}

/*
compare an devinfo_lua with a USB dev
undefined values (ID_NONE or NULL) match any
*/
static int compare_ldevinfo(devinfo_lua *ldevinfo,struct usb_device *dev) {
	return ( dev && ldevinfo
			&& (!ldevinfo->bus || strcmp(dev->bus->dirname,ldevinfo->bus) == 0)
			&& (!ldevinfo->dev || strcmp(dev->filename,ldevinfo->dev) == 0)
			&& (ldevinfo->vendor_id == DEVINFO_LUA_ID_NONE || dev->descriptor.idVendor == ldevinfo->vendor_id)
			&& (ldevinfo->product_id == DEVINFO_LUA_ID_NONE || dev->descriptor.idProduct == ldevinfo->product_id));
}

/*
get the connection user data specified by bus/path and push it on the stack
if nothing is found, returns 0 and pushes nothing
*/
int get_connection_udata_by_path(lua_State *L, const char *bus, const char *dev) {
	char dev_path[LIBUSB_PATH_MAX*2];
	if(!bus || !dev) {
		return 0;
	}
	sprintf(dev_path,"%s/%s",bus,dev);
	lua_getfield(L,LUA_REGISTRYINDEX,CHDK_CONNECTION_LIST);
	lua_getfield(L,-1,dev_path);
	//  TODO could check meta table
	if(lua_isuserdata(L,-1)) {
		lua_replace(L, -2); // move udata up to connection list
		return 1;
	} else {
		lua_pop(L, 2); // nil, connection list
		return 0;
	}
}

// TODO this will go way, use by_path
struct usb_device *find_device_ldev(devinfo_lua *ldev) {
	struct usb_bus *bus;
	struct usb_device *dev;

	bus=get_busses();
	for (; bus; bus = bus->next) {
		for (dev = bus->devices; dev; dev = dev->next) {
			if (dev->config) {
				if ((dev->config->interface->altsetting->bInterfaceClass==USB_CLASS_PTP)) {
					if(compare_ldevinfo(ldev,dev)) {
						return dev;
					}
				}
			}
		}
	}
	return NULL;
}

struct usb_device *find_device_by_path(const char *find_bus, const char *find_dev) {
	struct usb_bus *bus;
	struct usb_device *dev;

	bus=get_busses();
	for (; bus; bus = bus->next) {
		if(strcmp(find_bus,bus->dirname) != 0) {
			continue;
		}
		for (dev = bus->devices; dev; dev = dev->next) {
			if (dev->config) {
				if ((dev->config->interface->altsetting->bInterfaceClass==USB_CLASS_PTP)) {
					if(strcmp(find_dev,dev->filename) == 0) {
						return dev;
					}
				}
			}
		}
	}
	return NULL;
}

int open_camera_dev(struct usb_device *dev, PTP_USB *ptp_usb, PTPParams *params)
{
	uint16_t devstatus[2] = {0,0};
	int ret;
  	if(!dev) {
		printf("open_camera_dev: NULL dev\n");
		return 0;
	}
	find_endpoints(dev,&ptp_usb->inep,&ptp_usb->outep,&ptp_usb->intep);
	if(!init_ptp_usb(params, ptp_usb, dev)) {
		printf("open_camera_dev: init_ptp_usb 1 failed\n");
		return 0;
	}

	ret = ptp_opensession(params,1);
	if(ret!=PTP_RC_OK) {
// TODO temp debug - this appears to be needed on linux if other stuff grabbed the dev
		printf("open_camera_dev: ptp_opensession failed 0x%x\n",ret);
		ret = usb_ptp_device_reset(ptp_usb);
		if (ret<0)perror ("open_camera_dev:usb_ptp_device_reset()");
		/* get device status (devices likes that regardless of its result)*/
		ret = usb_ptp_get_device_status(ptp_usb,devstatus);
		if (ret<0) 
			perror ("usb_ptp_get_device_status()");
		else	{
			if (devstatus[1]==PTP_RC_OK) 
				printf ("Device status OK\n");
			else
				printf ("Device status 0x%04x\n",devstatus[1]);
		}

		close_usb(ptp_usb, dev);
		find_endpoints(dev,&ptp_usb->inep,&ptp_usb->outep,&ptp_usb->intep);
		if(!init_ptp_usb(params, ptp_usb, dev)) {
			printf("open_camera_dev: init_ptp_usb 2 failed\n");
			return 0;
		}
		ret=ptp_opensession(params,1);
		if(ret!=PTP_RC_OK) {
			printf("open_camera_dev: ptp_opensession 2 failed: 0x%x\n",ret);
			return 0;
		}

	}
	if (ptp_getdeviceinfo(params,&params->deviceinfo)!=PTP_RC_OK) {
		// TODO do we want to close here ?
		printf("Could not get device info!\n");
		close_camera(ptp_usb, params);
		return 0;
	}
	// TODO we could check camera CHDK, API version, etc here
	ptp_usb->connected = 1;
	return 1;
}

/*
chdk_connection=chdk.connection([devinfo])
devspec={
	bus="bus",
	dev="dev",
}
retreive or create the connection object for the specified device
each unique bus/dev combination has only one connection object. 
No attempt is made to verify that the device exists (it might be plugged/unplugged later anyway)
New connections start disconnected.
An existing connection may or may not be connected
if devinfo is absent, the dummy connection is returned
*/
static int chdk_connection(lua_State *L) {
	PTP_USB *ptp_usb;
	PTPParams *params;
	const char *bus="dummy";
	const char *dev="dummy";
	char dev_path[LIBUSB_PATH_MAX*2];

	if(lua_istable(L,1)) {
		lua_getfield(L,1,"dev");
		dev = lua_tostring(L,-1);
		lua_pop(L,1);

		lua_getfield(L,1,"bus");
		bus = lua_tostring(L,-1);
		lua_pop(L,1);
		if(!bus || !dev || strlen(dev) >= LIBUSB_PATH_MAX || strlen(bus) >= LIBUSB_PATH_MAX) {
			return luaL_error(L,"invalid device spec");
		}
	}

	// if connection to specified device exists, just return it
	if(get_connection_udata_by_path(L,bus,dev )) {
		return 1;
	}
	params = lua_newuserdata(L,sizeof(PTPParams));
	luaL_getmetatable(L, CHDK_CONNECTION_META);
	lua_setmetatable(L, -2);

	memset(params,0,sizeof(PTPParams));
	ptp_usb = malloc(sizeof(PTP_USB));
	params->data = ptp_usb; // this will be set on connect, but we want set so it can be collected even if we don't connect
	memset(ptp_usb,0,sizeof(PTP_USB));
	strcpy(ptp_usb->dev,dev);
	strcpy(ptp_usb->bus,bus);
	sprintf(dev_path,"%s/%s",bus,dev);

	// save in registry so we can easily identify / enumerate existing connections
	lua_getfield(L,LUA_REGISTRYINDEX,CHDK_CONNECTION_LIST);
	lua_pushvalue(L, -2); // our user data, for use as key
	lua_setfield(L, -2,dev_path); //set t[path]=userdata
	lua_pop(L,1); // done with t
	return 1;
}
/*
status[,errmsg]=con:connect()
*/
static int chdk_connect(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	struct usb_device *dev;
	
	// TODO might want to disconnect/reconnect, or check real connection status ? or options
	if(ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"already connected");
		return 2;
	}

	dev=find_device_by_path(ptp_usb->bus,ptp_usb->dev);
	if(!dev) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"no device");
		return 2;
	}
	if(open_camera_dev(dev,ptp_usb,params)) {
		lua_pushboolean(L,1);
		return 1;
	} else {
		ptp_usb->connected = 0;
		lua_pushboolean(L,0);
		lua_pushstring(L,"connection failed");
		return 2;
	}
}

/*
disconnect the connection
note under windows the device does not appear in in chdk.list_usb_devices() for a short time after disconnecting
*/
static int chdk_disconnect(lua_State *L) {
  	CHDK_CONNECTION_METHOD;

	close_connection(params,ptp_usb);
	lua_pushboolean(L,1);
	return 1;
}

static int chdk_is_connected(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	// TODO this should probably be more consistent over other PTP calls, #41
	// flag says we are connected, check usb and update flag
	if(ptp_usb->connected) { 
		ptp_usb->connected = check_connection_status(ptp_usb);
	}
	lua_pushboolean(L,ptp_usb->connected);
	return 1;
}

// major, minor = chdk.camera_api_version()
// TODO double return is annoying
// TODO we could just get this when we connect
static int chdk_camera_api_version(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	int major,minor;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	if(ptp_chdk_get_version(params,&major,&minor) ) {
		lua_pushnumber(L,major);
		lua_pushnumber(L,minor);
	} else {
		lua_pushboolean(L,0);
		lua_pushstring(L,"error");
	}
	return 2;
}

static int chdk_host_api_version(lua_State *L) {
	lua_newtable(L);
	lua_pushnumber(L,PTP_CHDK_VERSION_MAJOR);
	lua_setfield(L, -2, "MAJOR");
	lua_pushnumber(L,PTP_CHDK_VERSION_MINOR);
	lua_setfield(L, -2, "MINOR");
	return 1;
}

static int chdk_program_version(lua_State *L) {
	lua_newtable(L);
	lua_pushnumber(L,CHDKPTP_VERSION_MAJOR);
	lua_setfield(L, -2, "MAJOR");

	lua_pushnumber(L,CHDKPTP_VERSION_MINOR);
	lua_setfield(L, -2, "MINOR");

	lua_pushnumber(L,CHDKPTP_BUILD_NUM);
	lua_setfield(L, -2, "BUILD");

	lua_pushstring(L,CHDKPTP_REL_DESC);
	lua_setfield(L, -2, "DESC");

	lua_pushstring(L,__DATE__);
	lua_setfield(L, -2, "DATE");

	lua_pushstring(L,__TIME__);
	lua_setfield(L, -2, "TIME");

	lua_pushstring(L,__VERSION__);
	lua_setfield(L, -2, "COMPILER_VERSION");

	return 1;
}

/*
status[,err]=con:execlua("code")
status is true if script started successfully, false otherwise
con:get_script_id() will return the id of the started script
*/
static int chdk_execlua(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
    if (!ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}

	if(!ptp_chdk_exec_lua(params,(char *)luaL_optstring(L,2,""),&ptp_usb->script_id)) {
		lua_pushboolean(L,0);
		// if we got a script id, script request got as far as the the camera
		if(ptp_usb->script_id) {
			lua_pushstring(L,"syntax"); // caller can check messages for details
		} else {
			lua_pushstring(L,"failed");
		}
		return 2;
	}
	lua_pushboolean(L,1);
	return 1;
}

/*
push a new table onto the stack
{
	"bus" = "dirname", 
	"dev" = "filename", 
	"vendor_id" = VENDORID,
	"product_id" = PRODUCTID,
}
TODO may want to include interface/config info
*/
static void push_usb_dev_info(lua_State *L,struct usb_device *dev) {
	lua_createtable(L,0,4);
	lua_pushstring(L, dev->bus->dirname);
	lua_setfield(L, -2, "bus");
	lua_pushstring(L, dev->filename);
	lua_setfield(L, -2, "dev");
	lua_pushnumber(L, dev->descriptor.idVendor);
	lua_setfield(L, -2, "vendor_id");
	lua_pushnumber(L, dev->descriptor.idProduct);
	lua_setfield(L, -2, "product_id");
}

static int chdk_list_usb_devices(lua_State *L) {
	struct usb_bus *bus;
	struct usb_device *dev;
	int found=0;
	bus=get_busses();
	lua_newtable(L);
  	for (; bus; bus = bus->next) {
    	for (dev = bus->devices; dev; dev = dev->next) {
			if (!dev->config) {
				continue;
			}
			/* if it's a PTP list it */
			if ((dev->config->interface->altsetting->bInterfaceClass==USB_CLASS_PTP)) {
				push_usb_dev_info(L,dev);
				found++;
				lua_rawseti(L, -2, found); // add to array
			}
		}
	}
	return 1;
}

// TODO arg errors shouldn't be fatal
/*
status[,errmsg]=con:upload(src,dst)
*/
static int chdk_upload(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
    if (!ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	char *src = (char *)luaL_checkstring(L,2);
	char *dst = (char *)luaL_checkstring(L,3);
	if ( !ptp_chdk_upload(params,src,dst) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"upload failed");
		return 2;
	}
	lua_pushboolean(L,1);
	return 1;
}

// TODO arg errors shouldn't be fatal
/*
status[,errmsg]=con:download(src,dst)
*/
static int chdk_download(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
    if (!ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	char *src = (char *)luaL_checkstring(L,2);
	char *dst = (char *)luaL_checkstring(L,3);
	if ( !ptp_chdk_download(params,src,dst) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"download failed");
		return 2;
	}
	lua_pushboolean(L,1);
	return 1;
}

/*
isready,imgnum|errmsg=con:capture_ready()
isready: 
	false: local error in errmsg
	0: not ready
	0x10000000: remotecap not initialized, or timed out
	otherwise, lowest 3 bits: available data types.
imgnum:
	image number if data is available, otherwise 0
*/
static int chdk_capture_ready(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	if (!ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	int isready = 0;
	int imgnum = 0;
	if ( !ptp_chdk_rcisready(params,&isready,&imgnum) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"rcisready failed");
		return 2;
	}
	lua_pushinteger(L,isready);
	lua_pushinteger(L,imgnum);
	return 2;
}

/*
chunk[,errmsg]=con:capture_get_chunk(fmt)
fmt: data type (1: jpeg, 2: raw, 4:dng header)
must be a single type reported as available by con:capture_ready()
chunk:
false or
{
	size=number,
	offset=number|nil,
	last=bool
	data=lbuf
}
*/
static int chdk_capture_get_chunk(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	if (!ptp_usb->connected) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	int fmt = (unsigned)luaL_checknumber(L,2);
	ptp_chdk_rc_chunk chunk;
	if ( !ptp_chdk_rcgetchunk(params,fmt,&chunk) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"rcgetchunk failed");
		return 2;
	}
	lua_createtable(L,0,4);
	lua_pushinteger(L, chunk.size);
	lua_setfield(L, -2, "size");
	if((int32_t)chunk.offset != -1) {
		lua_pushinteger(L, chunk.offset);
		lua_setfield(L, -2, "offset");
	}
	lua_pushboolean(L, chunk.last);
	lua_setfield(L, -2, "last");

	lbuf_create(L,chunk.data,chunk.size,LBUF_FL_FREE); // data is allocated by ptp chunk, will be freed on gc
	lua_setfield(L, -2, "data");

	return 1;
}

/*
r,msg=con:getmem(address,count[,dest])
dest is
"string"
"number" TODO int or unsigned ?
-- not implemented yet ->
"array" array of numbers
"file",<filename>
"pointer" userdata to pass on to C elsewhere
default is string
*/
static int chdk_getmem(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	unsigned addr, count;
	const char *dest;
	char *buf;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	addr = (unsigned)luaL_checknumber(L,2);
	count = (unsigned)luaL_checknumber(L,3);
	dest = luaL_optstring(L,4,"string");

	// TODO check dest values
	if ( (buf = ptp_chdk_get_memory(params,addr,count)) == NULL ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"error getting memory");
		return 2;
	}
	if(strcmp(dest,"string") == 0) {
		lua_pushlstring(L,buf,count);
	} else if(strcmp(dest,"number") == 0) {
		lua_pushnumber(L,(lua_Number)(*(unsigned *)buf));
	}
	free(buf);
	return 1;
}

/*
TODO
status[,msg]=con:setmem(address,data)
data is a number (to bet set as a 32 bit int) or string
*/
static int chdk_setmem(lua_State *L) {
	lua_pushboolean(L,0);
	lua_pushstring(L,"not implemented yet, use lua poke()");
	return 2;
}

/*
ret=con:call_function(ptr,arg1,arg2...argN)
call a pointer directly from ptp code.
useful if lua is not available
args must be numbers, or pointers set up on the cam by other means
*/
static int chdk_call_function(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	int args[11];
	int ret;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	memset(args,0,sizeof(args));
	int size = lua_gettop(L)-1; // args excluding self
	if(size > 10 || size < 1) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"invalid number of arguments");
		return 2;
	}
	int i;
	for(i=2;i<=size+1;i++) {
		args[i-2] = (unsigned)luaL_checknumber(L,i);
	}
	if ( !ptp_chdk_call_function(params,args,size,&ret) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	}
	lua_pushnumber(L,ret);
	return 1;
}

static int chdk_script_support(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	unsigned status = 0;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
    if ( !ptp_chdk_get_script_support(params,&status) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	}
	lua_pushnumber(L,status);
	return 1;
}

/*
status[,errmsg]=con:script_status()
status={run:bool,msg:bool} or false
*/
static int chdk_script_status(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	unsigned status;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	if ( !ptp_chdk_get_script_status(params,&status) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	}
	lua_createtable(L,0,2);
	lua_pushboolean(L, status & PTP_CHDK_SCRIPT_STATUS_RUN);
	lua_setfield(L, -2, "run");
	lua_pushboolean(L, status & PTP_CHDK_SCRIPT_STATUS_MSG);
	lua_setfield(L, -2, "msg");
	return 1;
}
/*
lbuf[,errmsg]=con:get_live_data(lbuf,flags)
lbuf - lbuf to re-use, will be created if nil
*/
static int chdk_get_live_data(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	lBuf_t *buf = lbuf_getlbuf(L,2);
	unsigned flags=lua_tonumber(L,3);
	char *data=NULL;
	unsigned data_size = 0;
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	if ( !ptp_chdk_get_live_data(params,flags,&data,&data_size) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	}
	if(!data) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"no data");
		return 2;
	}
	if(!data_size) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"zero data size");
		return 2;
	}
	if(buf) {
		if(buf->flags & LBUF_FL_FREE) {
			free(buf->bytes);
		}
		buf->bytes = data;
		buf->len = data_size;
		buf->flags = LBUF_FL_FREE;
		lua_pushvalue(L,2); // copy it to stack top for return
	} else {
		lbuf_create(L,data,data_size,LBUF_FL_FREE);
	}
	return 1;
}

// TODO these assume numbers are 0 based and contiguous 
static const char* script_msg_type_to_name(unsigned type_id) {
	const char *names[]={"none","error","return","user"};
	if(type_id >= sizeof(names)/sizeof(names[0])) {
		return "unknown_msg_type";
	}
	return names[type_id];
}

static const char* script_msg_data_type_to_name(unsigned type_id) {
	const char *names[]={"unsupported","nil","boolean","integer","string","table"};
	if(type_id >= sizeof(names)/sizeof(names[0])) {
		return "unknown_msg_subtype";
	}
	return names[type_id];
}

static const char* script_msg_error_type_to_name(unsigned type_id) {
	const char *names[]={"none","compile","runtime"};
	if(type_id >= sizeof(names)/sizeof(names[0])) {
		return "unknown_error_subtype";
	}
	return names[type_id];
}

/*
msg[,errormessage]=con:read_msg()
msg is table on success, or false
{
value=<val>
script_id=<id>
mtype=<type_name>
msubtype=<subtype_name>
}
no message: type is set to 'none'

use chdku.wait_status to wait for messages
*/

static int chdk_read_msg(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	ptp_chdk_script_msg *msg = NULL;

	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}

	if(!ptp_chdk_read_script_msg(params,&msg)) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	}

	lua_createtable(L,0,4);
	lua_pushinteger(L, msg->script_id);
	lua_setfield(L, -2, "script_id");
	lua_pushstring(L, script_msg_type_to_name(msg->type));
	lua_setfield(L, -2, "type");

	switch(msg->type) {
		case PTP_CHDK_S_MSGTYPE_RET:
		case PTP_CHDK_S_MSGTYPE_USER:
			lua_pushstring(L, script_msg_data_type_to_name(msg->subtype));
			lua_setfield(L, -2, "subtype");
			switch(msg->subtype) {
				case PTP_CHDK_TYPE_UNSUPPORTED: // type name will be returned in data
				case PTP_CHDK_TYPE_STRING: 
				case PTP_CHDK_TYPE_TABLE: // tables are returned as a serialized string. 
										  // The user is responsible for unserializing, to allow different serialization methods
					lua_pushlstring(L, msg->data,msg->size);
					lua_setfield(L, -2, "value");
				break;
				case PTP_CHDK_TYPE_BOOLEAN:
					lua_pushboolean(L, *(int *)msg->data);
					lua_setfield(L, -2, "value");
				break;
				case PTP_CHDK_TYPE_INTEGER:
					lua_pushinteger(L, *(int *)msg->data);
					lua_setfield(L, -2, "value");
				break;
				// default or PTP_CHDK_TYPE_NIL - value is nil
			}
		break;
		case PTP_CHDK_S_MSGTYPE_ERR:
			lua_pushstring(L, script_msg_error_type_to_name(msg->subtype));
			lua_setfield(L, -2, "subtype");
			lua_pushlstring(L,msg->data,msg->size);
			lua_setfield(L, -2, "value");
		break;
		// default or MSGTYPE_NONE - value is nil
	}
	free(msg);
	return 1;
}

/*
status[,errormessage]=con:write_msg(msgstring,[script_id])
script_id defaults to the most recently started script
errormessage can be used to identify full queue etc
*/
static int chdk_write_msg(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	const char *str;
	size_t len;
	int status;
	int target_script_id = luaL_optinteger(L,3,ptp_usb->script_id);

	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}

	str = lua_tolstring(L,2,&len);
	if(!str || !len) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"invalid data");
		return 2;
	}

	if ( !ptp_chdk_write_script_msg(params,(char *)str,len,target_script_id,&status) ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"ptp error");
		return 2;
	} 

	switch(status) {
		case PTP_CHDK_S_MSGSTATUS_OK:
			lua_pushboolean(L,1);
			return 1;
		break;
		case PTP_CHDK_S_MSGSTATUS_NOTRUN:
			lua_pushboolean(L,0);
			lua_pushstring(L,"notrun");
		break;
		case PTP_CHDK_S_MSGSTATUS_QFULL:
			lua_pushboolean(L,0);
			lua_pushstring(L,"full");
		break;
		case PTP_CHDK_S_MSGSTATUS_BADID:
			lua_pushboolean(L,0);
			lua_pushstring(L,"badid");
		break;
		default:
			lua_pushboolean(L,0);
			lua_pushstring(L,"unexpected status code");
	}
	return 2;
}

/*
(script_id|false) = con:get_script_id()
returns the id of the most recently started script
script ids start at 1, and will be reset if the camera reboots
script id will be false if the last script request failed to reach the camera or no script has yet been run
scripts that encounter a syntax error still generate an id
*/
static int chdk_get_script_id(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	// TODO do we want to check connections status ?
	if(ptp_usb->script_id) {
		lua_pushnumber(L,ptp_usb->script_id);
	} else {
		lua_pushboolean(L,0);
	}
	return 1;
}

/*
TEMP testing
get_status_result,status[0],status[1]=con:dev_status()
*/
static int chdk_dev_status(lua_State *L) {
  	CHDK_CONNECTION_METHOD;
	uint16_t devstatus[2] = {0,0};
	int r = usb_ptp_get_device_status(ptp_usb,devstatus);
	lua_pushnumber(L,r);
	lua_pushnumber(L,devstatus[0]);
	lua_pushnumber(L,devstatus[1]);
	return 3;
}

/*
ptp_dev_info=con:get_ptp_devinfo()
ptp_dev_info = {
	manufacturer = "manufacturer"
	model = "model"
	device_version = "version""
	serial_number = "serialnum"
	max_packet_size = <number>
}
more fields may be added later
serial number may be NULL (=unset in table)
version does not match canon firmware version (e.g. d10 100a = "1-6.0.1.0")
*/
static int chdk_get_ptp_devinfo(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	// don't actually need to be connected to get this, but ensures we have valid data
	if ( !ptp_usb->connected ) {
		lua_pushboolean(L,0);
		lua_pushstring(L,"not connected");
		return 2;
	}
	lua_newtable(L);
	lua_pushstring(L, params->deviceinfo.Model);
	lua_setfield(L, -2, "model");
	lua_pushstring(L, params->deviceinfo.Manufacturer);
	lua_setfield(L, -2, "manufacturer");
	lua_pushstring(L, params->deviceinfo.DeviceVersion);
	lua_setfield(L, -2, "device_version");
	lua_pushstring(L, params->deviceinfo.SerialNumber);
	lua_setfield(L, -2, "serial_number");
	// TODO techincally this belongs to the endpoint
	// putting it here for informational purposes anyway so we can display in lua
	lua_pushnumber(L, params->max_packet_size);
	lua_setfield(L, -2, "max_packet_size");

	return 1;
}
/*
usb_dev_info=con:get_usb_devinfo()
usb_dev_info = {
	bus="bus"
	dev="dev"
	"vendor_id" = VENDORID, -- nil if no matching PTP capable device is connected
	"product_id" = PRODUCTID, -- nil if no matching PTP capable device is connected
}
*/
static int chdk_get_usb_devinfo(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	struct usb_device *dev;
	dev=find_device_by_path(ptp_usb->bus,ptp_usb->dev);
	if(dev) {
		push_usb_dev_info(L,dev);
	} else {
		lua_newtable(L);
		lua_pushstring(L, ptp_usb->bus);
		lua_setfield(L, -2, "bus");
		lua_pushstring(L, ptp_usb->dev);
		lua_setfield(L, -2, "dev");
	}
	return 1;
}

// TEMP TESTING
static int chdk_get_conlist(lua_State *L) {
	lua_getfield(L,LUA_REGISTRYINDEX,CHDK_CONNECTION_LIST);
	return 1;
}

static int chdk_reset_device(lua_State *L) {
	devinfo_lua ldevinfo;
	if(get_lua_devinfo(L,1,&ldevinfo)) {
		struct usb_device *dev = find_device_ldev(&ldevinfo);
		reset_device(dev);
	}
	return 0;
}

/*
most functions return result[,errormessage]
result is false or nil on error
some also throw errors with lua_error
TODO should be either all lua_error (with pcall) or not.
TODO many errors are still printed to the console
*/
static const luaL_Reg chdklib[] = {
  {"connection", chdk_connection},
  {"host_api_version", chdk_host_api_version},
  {"program_version", chdk_program_version},
  {"list_usb_devices", chdk_list_usb_devices},
  {"get_conlist", chdk_get_conlist}, // TEMP TESTING
  {"reset_device", chdk_reset_device}, // TEMP TESTING
  {NULL, NULL}
};

static int chdk_connection_gc(lua_State *L) {
	CHDK_CONNECTION_METHOD;

	//printf("collecting connection %s:%s\n",ptp_usb->bus,ptp_usb->dev);

	if(ptp_usb->connected) {
		//printf("disconnecting...");
		close_camera(ptp_usb,params);
		//printf("done\n");
	}
	free(ptp_usb);
	return 0;
}

static int chdk_reset_counters(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	ptp_usb->write_count = ptp_usb->read_count = 0;
	return 0;
}

static int chdk_get_counters(lua_State *L) {
	CHDK_CONNECTION_METHOD;
	lua_createtable(L,0,2);
	lua_pushnumber(L,ptp_usb->write_count);
	lua_setfield(L,-2,"write");
	lua_pushnumber(L,ptp_usb->read_count);
	lua_setfield(L,-2,"read");
	return 1;
}

/*
methods for connections
*/
static const luaL_Reg chdkconnection[] = {
  {"connect", chdk_connect},
  {"disconnect", chdk_disconnect},
  {"is_connected", chdk_is_connected},
  {"camera_api_version", chdk_camera_api_version},
  {"execlua", chdk_execlua},
  {"upload", chdk_upload},
  {"download", chdk_download},
  {"getmem", chdk_getmem},
  {"setmem", chdk_setmem},
  {"call_function", chdk_call_function},
  {"script_support", chdk_script_support},
  {"script_status", chdk_script_status},
  {"read_msg", chdk_read_msg},
  {"write_msg", chdk_write_msg},
  {"get_script_id", chdk_get_script_id},
  {"dev_status", chdk_dev_status},
  {"get_ptp_devinfo", chdk_get_ptp_devinfo},
  {"get_usb_devinfo", chdk_get_usb_devinfo}, // does not need to be connected, returns bus and dev at minimum
  {"get_live_data",chdk_get_live_data},
  {"capture_ready", chdk_capture_ready},
  {"capture_get_chunk", chdk_capture_get_chunk},
  {"reset_counters",chdk_reset_counters},
  {"get_counters",chdk_get_counters},
  {NULL, NULL}
};

/*
sys.sleep(ms)
NOTE this should not be used from gui code, since it blocks the whole gui
*/
static int syslib_sleep(lua_State *L) {
	unsigned ms=luaL_checknumber(L,1);
	// deal with the differences in sleep, usleep and windows Sleep
	if(ms > 1000) {
		sleep(ms/1000);
		ms=ms%1000;
	}
	usleep(ms*1000);
	return 0;
}

static int syslib_ostype(lua_State *L) {
	lua_pushstring(L,CHDKPTP_OSTYPE);
	return 1;
}

static int syslib_gettimeofday(lua_State *L) {
	struct timeval tv;
	gettimeofday(&tv,NULL);
	lua_pushnumber(L,tv.tv_sec);
	lua_pushnumber(L,tv.tv_usec);
	return 2;
}

/*
global copies of argc, argv for lua
*/
static int g_argc;
static char **g_argv;

/*
get argv[0]
*/
static int syslib_getcmd(lua_State *L) {
	lua_pushstring(L,g_argv[0]);
	return 1;
}
/*
get command line arguments as an array
args=sys.getargs()
*/
static int syslib_getargs(lua_State *L) {
	int i;
	lua_createtable(L,g_argc-1,0);
// make the command line args available in lua
	for(i = 1; i < g_argc; i++) {
		lua_pushstring(L,g_argv[i]);
		lua_rawseti(L, -2, i); // add to array
	}
	return 1;
}

/*
val=sys.getenv("name")
*/
static int syslib_getenv(lua_State *L) {
	const char *e = getenv(luaL_checkstring(L,1));
	if(e) {
		lua_pushstring(L,e);
		return 1;
	}
	return 0;
}

static int corevar_set_verbose(lua_State *L) {
	verbose = luaL_checknumber(L,1);
	return 0;
}
static int corevar_get_verbose(lua_State *L) {
	lua_pushnumber(L,verbose);
	return 1;
}

static const luaL_Reg lua_syslib[] = {
  {"sleep", syslib_sleep},
  {"ostype", syslib_ostype},
  {"gettimeofday", syslib_gettimeofday},
  {"getcmd",syslib_getcmd},
  {"getargs",syslib_getargs},
  {"getenv",syslib_getenv},
  {NULL, NULL}
};

// getters/setters for variables exposed to lua
static const luaL_Reg lua_corevar[] = {
  {"set_verbose", corevar_set_verbose},
  {"get_verbose", corevar_get_verbose},
  {NULL, NULL}
};

static int gui_inited;

// TODO we should allow loading IUP and CD with require
static int guisys_init(lua_State *L) {
#ifdef CHDKPTP_IUP
	if(!gui_inited) {
		gui_inited = 1;
		iuplua_open(L); 
#ifdef CHDKPTP_CD
		cdlua_open(L); 
		cdluaiup_open(L); 
#ifdef CHDKPTP_CD_PLUS
		cdInitContextPlus();
#endif // CD_PLUS
#endif // CD
	}
	lua_pushboolean(L,1);
	return 1;
#else // IUP
	lua_pushboolean(L,0);
	return 1;
#endif
}

static int uninit_gui_libs(lua_State *L) {
#ifdef CHDKPTP_IUP
	if(gui_inited) {
#ifdef CHDKPTP_CD
		cdlua_close(L);
#endif
		iuplua_close(L); 
//		IupClose(); // ???
		return 1;
	}
#endif
	return 0;
}

static int guisys_caps(lua_State *L) {
	lua_newtable(L);
#ifdef CHDKPTP_IUP
	lua_pushboolean(L,1);
	lua_setfield(L,-2,"IUP");
#endif
#ifdef CHDKPTP_CD
	lua_pushboolean(L,1);
	lua_setfield(L,-2,"CD");
#endif
	lua_pushboolean(L,1);
	lua_setfield(L,-2,"LIVEVIEW");
#ifdef CHDKPTP_CD_PLUS
	lua_pushboolean(L,1);
	lua_setfield(L,-2,"CDPLUS");
#endif
	return 1;
}

static const luaL_Reg lua_guisyslib[] = {
  {"init", guisys_init},
  {"caps", guisys_caps},
  {NULL, NULL}
};

static int chdkptp_registerlibs(lua_State *L) {
	/* set up meta table for connection object */
	luaL_newmetatable(L,CHDK_CONNECTION_META);
	lua_pushcfunction(L,chdk_connection_gc);
	lua_setfield(L,-2,"__gc");

	/* register functions that operate on a connection
	 * lua code can use them to implement OO connection interface
	*/
	luaL_register(L, "chdk_connection", chdkconnection);  

	/* register functions that don't require a connection */
	luaL_register(L, "chdk", chdklib);

	luaL_register(L, "sys", lua_syslib);
	luaL_register(L, "corevar", lua_corevar);
	luaL_register(L, "guisys", lua_guisyslib);

	liveimg_open(L);	
	
	// create a table to keep track of connections
	lua_newtable(L);
	// metatable for above
	luaL_newmetatable(L, CHDK_CONNECTION_LIST_META);
	lua_pushstring(L, "kv");  /* mode values: weak keys, weak values */
	lua_setfield(L, -2, "__mode");  /* metatable.__mode */
	lua_setmetatable(L,-2);
	lua_setfield(L,LUA_REGISTRYINDEX,CHDK_CONNECTION_LIST);
	return 1;
}

static int exec_lua_string(lua_State *L, const char *luacode) {
	int r;
	r=luaL_loadstring(L,luacode);
	if(r) {
		fprintf(stderr,"loadstring failed %d\n",r);
		fprintf(stderr,"error %s\n",lua_tostring(L, -1));
	} else {
		r=lua_pcall(L,0,LUA_MULTRET, 0);
		if(r) {
			fprintf(stderr,"pcall failed %d\n",r);
			fprintf(stderr,"error %s\n",lua_tostring(L, -1));
			// TODO should get stack trace
		}
	}
	return r==0;
}


/* main program  */
int main(int argc, char ** argv)
{
	g_argc = argc;
	g_argv = argv;
	/* register signal handlers */
//	signal(SIGINT, ptpcam_siginthandler);
	usb_init();
	lua_State *L = lua_open();
	luaL_openlibs(L);
	luaopen_lfs(L);
	lbuf_open(L);
	rawimg_open(L);	
	chdkptp_registerlibs(L);
	exec_lua_string(L,"require('main')");
	uninit_gui_libs(L);
	lua_close(L);
	// gc takes care of any open connections

	return 0;
}

