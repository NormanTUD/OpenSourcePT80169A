/*
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar
  14 rue de Plaisance, 75014 Paris, France
 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
*/
/*
   Schalter rechts:
   1
   L298N 1:
   4	In4	- Motor A forward	roller
   5	In3	- Motor A backward	roller
   6	In2	- Motor B forward	toparm
   7	In1	- Motor B backward	toparm
   L298N 2:
   8	In4	- Motor C forward	Armlinks
   9	In3	- Motor C backward	Armlinks
   10	In2	- Motor D forward	Armrechts
   11	In1	- Motor D backward	Armrechts

 */

# define enabledebug false
# define measuretime false

int debugCounter = 0;
int intendation_level = 0;
int pagecounter = 0;

bool arm_rechts_unten = NULL;
bool arm_links_unten = NULL;
bool roller_is_normalstellung = NULL;
bool toparm_is_normalstellung = NULL;
bool toparm_is_right = NULL;
// id HIGH = nach rechts,
// id + 1 HIGH = nach links

//const String left = "left";
//const String right = "right";
//const String up = "up";
//const String down = "down";

const short roller = 4;
//const String roller_name = "roller";
const short toparm = 6;
//const String toparm_name = "toparm";

const short armlinks = 8;
//const String armlinks_name = "left arm";

const short armrechts = 10;
//const String armrechts_name = "left arm";

const short lichtschranke_toparm = 12;
const short lichtschranke_roller = 13;
//const String lichtschranke_toparm_name = "toparm";

const int arm_seitenwechsel_zeit = 2300; // TODO!!! Abhängigkeit von eingestellten CM vom Toparm!!!

const int aussenarm_beweg_zeit = 600;

const int roller_zeit = 900;
const int roller_zeit_oben = 1500;

const int maxOutputLength = 50;
const int maxIncomingStringLength = 16;

char printableText[maxOutputLength];
char incomingString[maxIncomingStringLength];

String testtest;


void setup() {
#if enabledebug
	sprintf(printableText, "setup"); debug();
#endif 

	testtest.reserve(maxIncomingStringLength - 1);
	//Serial.begin(57600);
	Serial.begin(38400);

	set_pinmode(LED_BUILTIN, OUTPUT);
	set_pinmode(armlinks, OUTPUT);
	set_pinmode(armrechts, OUTPUT);
	set_pinmode(toparm, OUTPUT);

	set_pinmode(lichtschranke_toparm, INPUT);
	set_pinmode(lichtschranke_roller, INPUT);

	for (int j = 4; j <= 11; j++) {
		off(j);
	}

	Serial.setTimeout(500);

	linken_aussenarm_runter();
	rechten_aussenarm_runter();
	toparm_normalstellung();
	roller_normalstellung();
	release_book(false);

	sprintf(printableText, "done"); myPrint();
}

void getCharsFromSerial () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "getCharsFromSerial()"); debug();
#endif


	Serial.flush();
	if (Serial.available()) {
		testtest = Serial.readStringUntil('\n');
		testtest.trim();
		testtest.toCharArray(incomingString, maxIncomingStringLength);
		testtest = "";
	}

	intendation_level--;
}

void loop () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "loop"); debug();
#endif
	empfange_signal();
	intendation_level--;
}

void help () {
	sprintf(printableText, "Befehl<Enter>"); myPrint();

	sprintf(printableText, "\tBlaettern:"); myPrint();
	sprintf(printableText, "\t\tturn right"); myPrint();
	sprintf(printableText, "\t\tturn left"); myPrint();
	sprintf(printableText, "\t\tinsert"); myPrint();
	sprintf(printableText, "\t\trelease"); myPrint();

	sprintf(printableText, "\tArme bewegen:"); myPrint();
	sprintf(printableText, "\t\tleft/right arm up/down"); myPrint();
	sprintf(printableText, "\t\troller left/right"); myPrint();
	sprintf(printableText, "\t\ttoparm left/right"); myPrint();
	sprintf(printableText, "\t\troller/toparm normal"); myPrint();
	sprintf(printableText, "\t\tboth arms up/down"); myPrint();
	sprintf(printableText, "\t\tswitch toparm"); myPrint();

	sprintf(printableText, "\tLichtschranken:"); myPrint();
	sprintf(printableText, "\t\tlight roller/arm"); myPrint();

	sprintf(printableText, "\tDebug:"); myPrint();

	sprintf(printableText, "\t\ttest\tPorts 4-11"); myPrint();
}


int empfange_signal () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "empfange_signal"); debug();
#endif
		getCharsFromSerial();

		if(strlen(incomingString)) {
#if enabledebug
			sprintf(printableText, "strlen(incomingString): %d", strlen(incomingString)); debug();
#endif

#if enabledebug
			sprintf(printableText, "incomingString: >%s<", incomingString); debug();
#endif

			if(strcmp(incomingString, "turn right") == 0 || strcmp(incomingString, "p") == 0) { // Geht noch nicht
				nach_rechts_blaettern();
			} else if (strcmp(incomingString, "turn left") == 0) {
				//nach_links_blaettern();
#if enabledebug
				sprintf(printableText, "TODO!!! nach_links_blaettern"); debug();
#endif

			} else if (strcmp(incomingString, "both arms up") == 0) { // OK
				arm_links_unten = false;
				arm_rechts_unten = false;
				both_arms_up();
			} else if (strcmp(incomingString, "both arms down") == 0) { // OK
				arm_links_unten = false;
				arm_rechts_unten = false;
				both_arms_down();

			} else if (strcmp(incomingString, "right arm up") == 0 || strcmp(incomingString, "rau") == 0) { // OK
				rechten_aussenarm_hoch();
			} else if (strcmp(incomingString, "right arm down") == 0 || strcmp(incomingString, "rad") == 0) { // OK
				rechten_aussenarm_runter();

			} else if (strcmp(incomingString, "right arm up force") == 0 || strcmp(incomingString, "rauf") == 0) { // OK
				arm_rechts_unten = false;
				rechten_aussenarm_hoch();
			} else if (strcmp(incomingString, "right arm down force") == 0 || strcmp(incomingString, "radf") == 0) { // OK
				arm_rechts_unten = false;
				rechten_aussenarm_runter();

			} else if (strcmp(incomingString, "left arm up") == 0 || strcmp(incomingString, "lau") == 0) {  // OK
				arm_links_unten = false;
				linken_aussenarm_hoch();
			} else if (strcmp(incomingString, "left arm down") == 0 || strcmp(incomingString, "lad") == 0) { // OK
				arm_links_unten = false;
				linken_aussenarm_runter();

			} else if (strcmp(incomingString, "toparm right") == 0 || strcmp(incomingString, "tar") == 0) { // OK
				toparm_rechts();
			} else if (strcmp(incomingString, "toparm left") == 0 || strcmp(incomingString, "tal") == 0) { // OK
				toparm_links();

			} else if (strcmp(incomingString, "roller right") == 0) { // OK
				roller_rechts();
			} else if (strcmp(incomingString, "roller left") == 0) { // OK
				roller_links();

			} else if (strcmp(incomingString, "roller normal") == 0) { // OK
				roller_normalstellung();
			} else if (strcmp(incomingString, "toparm normal") == 0) { // OK
				toparm_normalstellung();

			} else if (strcmp(incomingString, "switch toparm") == 0 || strcmp(incomingString, "s") == 0) { // OK
				switch_toparm();

			} else if (strcmp(incomingString, "release") == 0) { // OK
				release_book(true);
			} else if (strcmp(incomingString, "insert") == 0) { // OK
				insert_book();

			} else if (strcmp(incomingString, "light roller") == 0) {
				sprintf(printableText, "%d", objekt_ist_in_lichtschranke(lichtschranke_roller)); myPrint();
			} else if (strcmp(incomingString, "light arm") == 0) {
				sprintf(printableText, "%d", objekt_ist_in_lichtschranke(lichtschranke_toparm)); myPrint();

/*
			} else if (strcmp(incomingString, "1") == 0) {
				test_port(1);
			} else if (strcmp(incomingString, "2") == 0) {
				test_port(2);
			} else if (strcmp(incomingString, "3") == 0) {
				test_port(3);
			} else if (strcmp(incomingString, "4") == 0) {
				test_port(4);
			} else if (strcmp(incomingString, "5") == 0) {
				test_port(5);
			} else if (strcmp(incomingString, "6") == 0) {
				test_port(6);
			} else if (strcmp(incomingString, "7") == 0) {
				test_port(7);
			} else if (strcmp(incomingString, "8") == 0) {
				test_port(8);
			} else if (strcmp(incomingString, "9") == 0) {
				test_port(9);
			} else if (strcmp(incomingString, "10") == 0) {
				test_port(10);
			} else if (strcmp(incomingString, "11") == 0) {
				test_port(11);

			} else if (strcmp(incomingString, "test") == 0) {
#if enabledebug
				sprintf(printableText, "Testing ports 4-11"); debug();
#endif
				for (int a = 4; a <= 11; a++) {
					test_port(a);
				}
*/

			} else if (strcmp(incomingString, "50") == 0) {
				for (int a = 1; a <= 50; a++) {
					nach_rechts_blaettern();
				}

			} else if (strcmp(incomingString, "help") == 0) {
				help();
			} else {
				sprintf(printableText, "Unknown String: %s", incomingString); myPrint();
				help();
			}
		}
		sprintf(incomingString, "");
		memset(incomingString, 0, sizeof(incomingString));   // Clear contents of Buffer
//	}

	warte(300);

	intendation_level--;
}

void insert_book () {
	linken_aussenarm_runter();
	rechten_aussenarm_runter();
	sprintf(printableText, "done"); myPrint();
}


void release_book (bool showdone) {
	toparm_normalstellung();
	linken_aussenarm_hoch();
	rechten_aussenarm_hoch();
	if(showdone) {
		sprintf(printableText, "done"); myPrint();
	}
}

void toparm_normalstellung() {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_normalstellung"); debug();
#endif

	if(toparm_is_normalstellung == false || toparm_is_normalstellung == NULL) {
		int rotation_time = 300;
		int toparm_links = toparm + 1;

		// Aus Lichtschranke rausholen
		while (objekt_ist_in_lichtschranke(lichtschranke_toparm)) {
#if enabledebug
			sprintf(printableText, "Aus Lichtschranke rausholen"); debug();
#endif
			on(toparm_links);
			warte(rotation_time);
			off(toparm_links);
		}

		// In Lichtschranke reinbringen
		while (!objekt_ist_in_lichtschranke(lichtschranke_toparm)) {
#if enabledebug
			sprintf(printableText, "In Lichtschranke reinbringen"); debug();
#endif
			on(toparm);
			warte(rotation_time);
			off(toparm);
		}
		toparm_is_normalstellung = true;
	}
#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO NULL 0"); debug();
#endif
	toparm_is_right = NULL;
	toparm_is_normalstellung = false;
	intendation_level--;
}

void switch_toparm () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "switch_toparm"); debug();
#endif

	intendation_level++;
	short toparm_links = toparm + 1;

	short movetime = 3000;

	off(toparm);
	off(toparm + 1);

	if(toparm_is_right == NULL || toparm_is_right == false) {
		on(toparm);
		warte(movetime);
		off(toparm);
#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO TRUE 1"); debug();
#endif
		toparm_is_right = true;

	} else if (toparm_is_right == true) {
		on(toparm_links);
		warte(movetime);
		off(toparm_links);
#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO FALSE 2"); debug();
#endif
		toparm_is_right = false;
	}
	toparm_is_normalstellung = false;

	sprintf(printableText, "done"); myPrint();
	intendation_level--;
}

void roller_normalstellung() {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "roller_normalstellung"); debug();
#endif

	if(roller_is_normalstellung != true || roller_is_normalstellung == NULL) {
		int rotation_time = 30;

		/*
		   while (objekt_ist_in_lichtschranke(lichtschranke_roller)) {
		   roller_links_mit_zeit(rotation_time);
		   }
		 */

		while (!objekt_ist_in_lichtschranke(lichtschranke_roller)) {
			roller_rechts_mit_zeit(rotation_time);
		}
		roller_links_mit_zeit(90);
		roller_is_normalstellung = true;
	}
	intendation_level--;
}

void oben_normalstellung() {
	rechten_aussenarm_runter();
	linken_aussenarm_runter();
}

void alles_auf_normalstellung () {
	toparm_normalstellung();
	oben_normalstellung();
	roller_normalstellung();
}

void both_arms_up () {
	rechten_aussenarm_hoch();
	linken_aussenarm_hoch();
}

void both_arms_down () {
	rechten_aussenarm_runter();
	linken_aussenarm_runter();
}

void nach_rechts_blaettern () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "nach_rechts_blaettern"); debug();
#endif

#if measuretime
	unsigned int StartTime = millis();
#endif

	// Rechten aussenarm runter
	// Rechten aussenarm hoch
	// Rechten aussenarm aus
	// TODO!!! roller in Normalstellung
	// toparm nach rechts
	// roller nach rechts drehen
	// toparm nach links
	// toparm aus

	// roller 2x drehen irgendwo noch rein!!!
	alles_auf_normalstellung();

	toparm_rechts();
	rechten_aussenarm_hoch();
	roller_rechts();

	rechten_aussenarm_runter();

	toparm_links_erstes_drittel();

	roller_links_mit_zeit(roller_zeit_oben);

	toparm_links_rest();

	linken_aussenarm_hoch();
	if(pagecounter && pagecounter % 20 == 0) {
		roller_links_mit_zeit(60);
	}
	
	linken_aussenarm_runter();

	toparm_normalstellung();

	pagecounter = pagecounter + 1;
	sprintf(printableText, "done"); myPrint();
#if measuretime
	unsigned int CurrentTime = millis();
	unsigned int ElapsedTime = CurrentTime - StartTime;
	//sprintf(printableText, "MEASURED TIME: %s", String(ElapsedTime)); myPrint();
	Serial.print("MEASURED TIME: ");
	Serial.println(int(ElapsedTime / 1000));
#endif
	intendation_level--;
}

void roller_links_mit_zeit (int zeit) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "roller_links_mit_zeit(%d)", zeit); debug();
#endif
	bewege_arm_mit_zeit(roller, 1, zeit);
	intendation_level--;
}

void roller_links () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "roller_links"); debug();
#endif
	roller_is_normalstellung = false;
	roller_links_mit_zeit(roller_zeit);
	intendation_level--;
}

void roller_rechts_mit_zeit (int zeit) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "roller_rechts_mit_zeit(%d)", zeit); debug();
#endif
	bewege_arm_mit_zeit(roller, 0, zeit);
	intendation_level--;
}

void roller_rechts () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "roller_rechts"); debug();
#endif
	roller_is_normalstellung = false;
	bewege_arm_mit_zeit(roller, 0, roller_zeit);
	intendation_level--;
}

void toparm_links_mit_zeit (int zeit) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_links_mit_zeit(%d)", zeit); debug();
#endif

	off(toparm);
	off(toparm + 1);

	on(toparm + 1);
	warte(zeit);
	off(toparm + 1);

#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO FALSE 3"); debug();
#endif
	toparm_is_right = false;
	toparm_is_normalstellung = false;


	intendation_level--;
}

void toparm_rechts () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_rechts"); debug();
#endif


	off(toparm);
	off(toparm + 1);

	on(toparm);
	warte(2500);
	off(toparm);

#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO TRUE 4"); debug();
#endif
	toparm_is_right = true;
	toparm_is_normalstellung = false;

	intendation_level--;
}

void toparm_links () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_links"); debug();
#endif
	toparm_links_mit_zeit(arm_seitenwechsel_zeit);
#if enabledebug
	sprintf(printableText, "SETTING TOPARM TO FALSE 5"); debug();
#endif
	toparm_is_right = false;
	toparm_is_normalstellung = false;
	intendation_level--;
}

void toparm_links_erstes_drittel () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_links_erstes_drittel"); debug();
#endif


	off(toparm);
	off(toparm + 1);

	on(toparm + 1);
	warte(2600);
	off(toparm + 1);

	toparm_is_normalstellung = false;

/*
	on(toparm + 1);
	//warte(int(arm_seitenwechsel_zeit / 3));
	warte(int(arm_seitenwechsel_zeit / 2));
	off(toparm + 1);
*/

	//toparm_links_mit_zeit(int(arm_halbe_bewegung_zeit));
	intendation_level--;
}

void toparm_links_rest () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_links"); debug();
#endif

	on(toparm + 1);
	warte(3500);
	off(toparm + 1);

	intendation_level--;
}

void toparm_rechts_erstes_drittel () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_rechts_erstes_drittel"); debug();
#endif

	off(toparm);
	off(toparm + 1);
	on(toparm);
	warte(1600);
	off(toparm);

	intendation_level--;
}

void toparm_rechts_rest () {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "toparm_rechts_rest"); debug();
#endif

	on(toparm);
	//warte(int(arm_seitenwechsel_zeit - (arm_seitenwechsel_zeit / 3)));
	warte(int(arm_seitenwechsel_zeit / 2));
	off(toparm);

	intendation_level--;
}

void bewege_arm_mit_zeit (short arm, short richtungs_id, int zeit) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "bewege_arm_mit_zeit(arm = %d, richtungs_id = %d)", arm, richtungs_id); debug();
#endif
	off(arm);
	off(arm + 1);

	on(arm + richtungs_id);
	warte(zeit);
	off(arm + richtungs_id);

	intendation_level--;
}

void linken_aussenarm_hoch () {
	intendation_level++;
	if(arm_links_unten != false || arm_links_unten == NULL) {
		arm_links_unten = false;
#if enabledebug
		sprintf(printableText, "linken_aussenarm_hoch"); debug();
#endif
		aussenarm_bewegen(armlinks, 1);
	} else {
#if enabledebug
		sprintf(printableText, "linken_aussenarm_hoch not executed"); debug();
#endif
	}
	intendation_level--;
}

void linken_aussenarm_runter () {
	intendation_level++;
	if(arm_links_unten != true || arm_links_unten == NULL) {
		arm_links_unten = true;
#if enabledebug
		sprintf(printableText, "linken_aussenarm_runter"); debug();
#endif
		aussenarm_bewegen(armlinks, 0);
	}
	intendation_level--;
}

void rechten_aussenarm_runter () {
	intendation_level++;
	if(arm_rechts_unten != true || arm_rechts_unten == NULL) {
		arm_rechts_unten = true;
#if enabledebug
		sprintf(printableText, "rechten_aussenarm_runter"); debug();
#endif
		aussenarm_bewegen(armrechts, 0);
	}
	intendation_level--;
}

void rechten_aussenarm_hoch () {
	intendation_level++;
	if(arm_rechts_unten != false || arm_rechts_unten == NULL) {
		arm_rechts_unten = false;
#if enabledebug
		sprintf(printableText, "rechten_aussenarm_hoch"); debug();
#endif
		aussenarm_bewegen(armrechts, 1);
	}
	intendation_level--;
}

void aussenarm_bewegen (int arm_id, int richtungs_id) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "aussenarm_bewegen(arm_id = %d, richtungs_id = %d)", arm_id, richtungs_id); debug();
#endif

	off(arm_id);
	off(arm_id + 1);

	on(arm_id + richtungs_id);
	warte(aussenarm_beweg_zeit);
	off(arm_id + richtungs_id);

	intendation_level--;
}

void warte (int zeit) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "warte(int zeit = %d)", zeit); debug();
#endif
	delay(zeit);
	intendation_level--;
}

void on (int port) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "on(%d)", port); debug();
#endif
	myWrite(port, HIGH);
	intendation_level--;
}

void off (int port) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "off(%d)", port); debug();
#endif
	myWrite(port, LOW);
	intendation_level--;
}

void myWrite (int port, int status) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "Writing %d to port %d", status, port); debug();
#endif
	digitalWrite(port, status);
	intendation_level--;
}

void myPrint () {
	Serial.println(printableText);
	sprintf(printableText, "");
}

void debug () {
# ifdef enabledebug
	if(debugCounter >= 32767) {
		debugCounter = 0;
	}

	Serial.print(debugCounter);
	Serial.print(": ");
	for (int i = 0; i != intendation_level; i++) {
		Serial.print(" ");
	}
	Serial.println(printableText);
	sprintf(printableText, "");
	debugCounter = debugCounter + 1;
# endif
}

void set_pinmode (int pin, int mode) {
	intendation_level++;
#if enabledebug
	sprintf(printableText, "set_pinmode(int pin = %d, int mode = %d)", pin, mode); debug();
#endif
	pinMode(pin, mode);
	intendation_level--;
}

boolean objekt_ist_in_lichtschranke(int thisLichtschranke) {
	int value = digitalRead(thisLichtschranke);
#if enabledebug
	sprintf(printableText, "%d", value); debug();
#endif

	if(value) {
		return true;
	}

	return false;
}
