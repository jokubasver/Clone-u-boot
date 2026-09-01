/*
 * (C) Copyright 2020 Hardkernel Co., Ltd
 *
 * SPDX-License-Identifier:     GPL-2.0+
 */

#include <common.h>
#include <dm.h>
#include <asm/gpio.h>
#include <power/fuel_gauge.h>
#include <power/charge_animation.h>
#include <odroidgoa_status.h>

/*
 * charge_extrem_low_power() uses 'low_power_voltage + 50' as its exit line:
 * while charging, the terminal voltage reading is inflated by charge current
 * through the battery's internal resistance, so +50mV margin is required
 * before trusting it above the nominal line.
 *
 * This gate runs with no charger while the system draws load: the reading
 * is deflated by I*R sag instead, so the margin goes the other direction.
 * poweroff only below 'low_power_voltage - 50'; the pair (3055-50, 3055+50)
 * forms hysteresis around the nominal dtb line.
 */
#define LOW_POWER_OFFSET	50
#define DEFAULT_LOW_POWER_VOLTAGE	3055

#define PWR_LED_GPIO	18	/* GPIO0_C2 */
#define DC_DET_GPIO	11	/* GPIO0_B3 */
#define CHG_LED_GPIO	13	/* GPIO0_B5 */

void board_chg_led(void)
{
	gpio_request(CHG_LED_GPIO, "chg_led");
	/* default off, controlled by charge animation logic */
	gpio_direction_output(CHG_LED_GPIO, 0);
	gpio_free(CHG_LED_GPIO);
}

void board_pwr_led(bool on)
{
	gpio_request(PWR_LED_GPIO, "pwr_led");
	gpio_direction_output(PWR_LED_GPIO, on);
	gpio_free(PWR_LED_GPIO);
}

int odroid_check_dcjack(void)
{
	/* set pwr led on by default */
	board_pwr_led(true);

	gpio_request(DC_DET_GPIO, "dc_det_gpio");
	if (gpio_get_value(DC_DET_GPIO)) {
		debug("dc jack is NOT connected\n");
		return 0;
	} else {
		debug("dc jack is connected\n");
		return 1;
	}
}

static int board_get_low_power_voltage(void)
{
	struct udevice *dev;
	struct charge_animation_pdata *pdata;

	if (!uclass_get_device(UCLASS_CHARGE_DISPLAY, 0, &dev)) {
		pdata = dev_get_platdata(dev);
		if (pdata->low_power_voltage > LOW_POWER_OFFSET)
			return pdata->low_power_voltage - LOW_POWER_OFFSET;
	}

	return DEFAULT_LOW_POWER_VOLTAGE - LOW_POWER_OFFSET;
}

int board_check_power(void)
{
	struct udevice *fg;
	int battery;
	int chrg_online;
	int threshold;
	char str[32];

	board_chg_led();

	if (uclass_get_device(UCLASS_FG, 0, &fg)) {
		debug("Can't find FG, skip power check\n");
		return 0;
	}

	/* set pwr led on by default */
	board_pwr_led(true);

	battery = fuel_gauge_get_voltage(fg);
	if (battery < 0)
		return 0;

	/* charger detection by PMIC plug-in status, not DC_DET gpio */
	chrg_online = fuel_gauge_get_chrg_online(fg);

	threshold = board_get_low_power_voltage();

	/* charger online or battery above the extrem-low-power line */
	if (chrg_online > 0 || battery >= threshold)
		return 0;

	debug("low battery (%d) without charger, threshold=%d\n",
	      battery, threshold);
	sprintf(str, "voltage level : %d.%dV", (battery / 1000), (battery % 1000));
	odroid_display_status(LOGO_MODE_LOW_BATT, LOGO_STORAGE_ANYWHERE, str);
	odroid_wait_pwrkey();

	return -1;
}
