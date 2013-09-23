/* ptpcam.h
 *
 * Copyright (C) 2001-2005 Mariusz Woloszyn <emsi@ipartners.pl>
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
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 */
#ifndef __PTPCAM_H__
#define __PTPCAM_H__

#define USB_BULK_READ usb_bulk_read
#define USB_BULK_WRITE usb_bulk_write

/*
 * structures
 */

// connection data
// TODO might be more convenient to use this as the meta data and put in a pointer to PTPParams ?
// TODO - guess this is win only
#ifndef LIBUSB_PATH_MAX
#define LIBUSB_PATH_MAX (PATH_MAX + 1)
#endif
typedef struct {
	usb_dev_handle* handle;
	int inep;
	int outep;
	int intep;
	int script_id;
	int timeout;
	int connected; // soft check without actually trying to access usb
	char bus[LIBUSB_PATH_MAX]; // identifies what device this is for
	char dev[LIBUSB_PATH_MAX]; // TODO this may not work out, libusb on win changes the dev number on reset
	// counters
	uint64_t write_count;
	uint64_t read_count;
} PTP_USB;

/*
 * variables
 */

/* one global variable */
// TODO
extern short verbose;

/*
 * functions
 */

//void ptpcam_siginthandler(int signum);

struct usb_bus* init_usb(void);
void close_usb(PTP_USB* ptp_usb, struct usb_device* dev);
int init_ptp_usb (PTPParams*, PTP_USB*, struct usb_device*);
void clear_stall(PTP_USB* ptp_usb);

int usb_get_endpoint_status(PTP_USB* ptp_usb, int ep, uint16_t* status);
int usb_clear_stall_feature(PTP_USB* ptp_usb, int ep);
int open_camera (int busn, int devn, short force, PTP_USB *ptp_usb, PTPParams *params, struct usb_device **dev);
void close_camera (PTP_USB *ptp_usb, PTPParams *params);
struct usb_device *find_device_by_path(const char *find_bus, const char *find_dev);
#endif /* __PTPCAM_H__ */
