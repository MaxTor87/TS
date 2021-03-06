﻿//+-----------------------------------------------------------------------+
//|                                                     MIGLIORINO TS.mq5 |
//| Copyright © 2020, Davide Dallari, Simone Rubessi & Massimo Torricelli |
//+-----------------------------------------------------------------------+

#property copyright   "Copyright © 2020, Davide Dallari, Simone Rubessi & Massimo Torricelli"
#define VERSION "1.04"
#property version VERSION
#property description "Migliorino strategy - Aggiunta di Telegram"
#define desc_agg "Aggiunto il cambio parametri Migliorino e la disabilitazione di Telegram"

//+------------------------------------------------------------------+
//|   MASSIMO - Inizializzazione variabili                           |
//+------------------------------------------------------------------+
#include <Comment.mqh>
#include <Telegram.mqh>

//--- Variabili Telegram
long chat_ID = -1001429715820; //Questo serve SOLO se si vuole mandare un messaggio dalla funzione OnInit() dove non si sa quale chat parla
bool msg_sent = 0; //Verifica che non sia già stato mandato un messaggio relativo all'oltrepassamento della BdM

//--- Variabili per menù tastiera
#define LOCK_TEXT       "Lock"
#define UNLOCK_TEXT     "Unlock"
#define LOCK_CODE       "\xF512"
#define UNLOCK_CODE     "\xF513"

const ENUM_TIMEFRAMES _periods[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1,PERIOD_MN1};

input bool use_Telegram = true;

//+------------------------------------------------------------------+
//|   DAVIDE - Inizializzazione variabili                            |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

int MIGL1definition;
int MIGL2definition;
int MIGL3definition;

input bool MIGL_in = true;          //IN - Migliorino
input bool MIGL_out = true; ;        //OUT - Migliorino

/* ------> SPOSTATO IN OnInit()
input int PeriodMigl1 = 768;        //Migliorino1 - periodo di riferimento
input double PercMigl1 = 0.5;       //Migliorino1 - % banda
input int PeriodMigl2 = 384;        //Migliorino2 - periodo di riferimento
input double PercMigl2 = 0.4;       //Migliorino2 - % banda
input int PeriodMigl3 = 194;        //Migliorino3 - periodo di riferimento
input double PercMigl3 = 0.2;       //Migliorino3 - % banda
*/
double LotsToBuy = 1.00;            //lotti comprati
const int Commission = 0;           //commissione per ogni deal da 1 lotto

const int Dim = 6;                  //dimensione del vettore delle medie mobili e delle candele (va aggiunto +1)
const int Dim_HA = 2;               //dimensione del vettore delle candele Heiken Ashi (va aggiunto +1)
string position = "";               //posizione: è la posizione in cui si è entrati
double Balance_max = 0;             //bilancio massimo raggiunto
double DD_max = 0.001;              //drawdown massimo raggiunto
int bars = 0;                       //contatore di candele
bool new_bar = false;               //variabile che indica se siamo appena passati a una nuova candela

int contatore=0;
int file_count=0;                   //progressivo per la creazione degli screenshot
int bars_count=4;                   //conta le candle di attesa dopo le quali avvisare di nuovo l'utente dell'imminente ingresso
datetime time_to_call=TimeCurrent();//orario in cui avvisare l'utente dell'imminente ingresso

bool signal_crossed_down = false;   //variabile che indica se il segnale ha oltrepassato le 3 bande inferiori
bool signal_crossed_up = false;     //variabile che indica se il segnale ha oltrepassato le 3 bande superiori
bool bands_crossed_down = false;    //variabile che indica se ciscuna banda ha oltrepassato al ribasso la propria banda più lenta
bool bands_crossed_up = false;      //variabile che indica se ciscuna banda ha oltrepassato al rialzo la propria banda più lenta

//+------------------------------------------------------------------+
//|   CMyBot                                                         |
//+------------------------------------------------------------------+
class CMyBot: public CCustomBot
  {
private:
   ENUM_LANGUAGES    m_lang;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   string            m_template;
   CArrayString      m_templates;
   
   bool              m_lock_state;

public:
   //+------------------------------------------------------------------+
   void CMyBot::CMyBot(void)
     {
      m_lock_state=true;
     }
   //+------------------------------------------------------------------+   
   void Language(const ENUM_LANGUAGES _lang){m_lang=_lang;}

   //+------------------------------------------------------------------+
   int Templates(const string _list)
     {
      m_templates.Clear();
      //--- parsing
      string text=StringTrim(_list);
      if(text=="")
         return(0);

      //---
      while(StringReplace(text,"  "," ")>0);
      StringReplace(text,";"," ");
      StringReplace(text,","," ");

      //---
      string array[];
      int amount=StringSplit(text,' ',array);
      amount=fmin(amount,5);

      for(int i=0; i<amount; i++)
        {
         array[i]=StringTrim(array[i]);
         if(array[i]!="")
            m_templates.Add(array[i]);
        }

      return(amount);
     }

   //+------------------------------------------------------------------+   
   int SendScreenShot(const long _chat_id,
                      const string _symbol,
                      const ENUM_TIMEFRAMES _period,
                      const string _template=NULL)
     {
      int result=0;
      if (use_Telegram)
      {
         
   
         long chart_id=ChartOpen(_symbol,_period);
         if(chart_id==0)
            return(ERR_CHART_NOT_FOUND);
   
         ChartSetInteger(ChartID(),CHART_BRING_TO_TOP,true);
   
         //--- updates chart
         //int wait=60;
         int wait=5;
         while(--wait>0)
           {
            if(SeriesInfoInteger(_symbol,_period,SERIES_SYNCHRONIZED))
               break;
            Sleep(500);
           }
   
         if(_template!=NULL)
            if(!ChartApplyTemplate(chart_id,_template))
               PrintError(_LastError,InpLanguage);
   
         ChartRedraw(chart_id);
         Sleep(500);
   
         ChartSetInteger(chart_id,CHART_SHOW_GRID,false);
   
         ChartSetInteger(chart_id,CHART_SHOW_PERIOD_SEP,false);
   
         string filename=StringFormat("%s%d.gif",_symbol,_period);
   
         if(FileIsExist(filename))
            FileDelete(filename);
         ChartRedraw(chart_id);
   
         Sleep(100);
   
         if(ChartScreenShot(chart_id,filename,800,600,ALIGN_RIGHT))
           {
            Sleep(100);
   
            bot.SendChatAction(_chat_id,ACTION_UPLOAD_PHOTO);
   
            //--- waitng 30 sec for save screenshot
            wait=60;
            while(!FileIsExist(filename) && --wait>0)
               Sleep(500);
   
            //---
            if(FileIsExist(filename))
              {
               string screen_id;
               //result=bot.SendPhoto(_chat_id,filename,screen_id,_symbol+"_"+StringSubstr(EnumToString(_period),7));
               result=bot.SendPhoto(screen_id,_chat_id,filename,_symbol+"_"+StringSubstr(EnumToString(_period),7));
              }
            else
              {
               string mask=m_lang==LANGUAGE_EN?"Screenshot file '%s' not created.":"Файл скриншота '%s' не создан.";
               PrintFormat(mask,filename);
              }
   
           }
   
         ChartClose(chart_id);
         }         
         return(result);
     }

   //+------------------------------------------------------------------+   
   void ProcessMessages(void)
     {

#define EMOJI_TOP    "\xF51D"
#define EMOJI_BACK   "\xF519"
#define KEYB_MAIN    (m_lang==LANGUAGE_EN)?"[[\"Account Info\",\"Altro...\"],[\"Quotes\"],[\"Charts\"],[\"Ordini\"]]":"[[\"Информация\"],[\"Котировки\"],[\"Графики\"]]"
#define KEYB_SYMBOLS "[[\""+EMOJI_TOP+"\",\"GBPUSD\",\"EURUSD\"],[\"AUDUSD\",\"USDJPY\",\"EURJPY\"],[\"USDCAD\",\"USDCHF\",\"EURCHF\"]]"
#define KEYB_PERIODS "[[\""+EMOJI_TOP+"\",\"M1\",\"M5\",\"M15\"],[\""+EMOJI_BACK+"\",\"M30\",\"H1\",\"H4\"],[\" \",\"D1\",\"W1\",\"MN1\"]]"
#define KEYB_TS "[[\""+EMOJI_TOP+"\",\""+EMOJI_BACK+"\"],[\"SELL\",\"BUY\"],[\"Chiudi tutte le posizioni\"],[\"\xF512 Lock\"]]"
#define KEYB_ALTRO "[[\""+EMOJI_TOP+"\",\""+EMOJI_BACK+"\"],[\"Kill TS\"]]"
      
      for(int i=0;i<m_chats.Total();i++)
        {
         CCustomChat *chat=m_chats.GetNodeAtIndex(i);
         
         if(!chat.m_new_one.done)
           {
            chat.m_new_one.done=true;
            string text=chat.m_new_one.message_text;
            
            Print("Messaggio ricevuto: ", text);

            //--- start
            if(text=="/start" || text=="/help" || text=="/commands@testDMtradingbot")
              {
               chat.m_state=0;
               string msg="The bot works with your trading account:\n";
               msg+="/info - get account information\n";
               msg+="/quotes - get quotes\n";
               msg+="/charts - get chart images\n";

               if(m_lang==LANGUAGE_RU)
                 {
                  msg="Бот работает с вашим торговым счетом:\n";
                  msg+="/info - запросить информацию по счету\n";
                  msg+="/quotes - запросить котировки\n";
                  msg+="/charts - запросить график\n";
                 }

               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
               continue;
              }

            //---
            if(text==EMOJI_TOP)
              {
               chat.m_state=0;
               string msg=(m_lang==LANGUAGE_EN)?"Choose a menu item":"Выберите пункт меню";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
               continue;
              }

            //---
            if(text==EMOJI_BACK)
              {
               if(chat.m_state==31)
                 {
                  chat.m_state=3;
                  string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like 'EURUSD'":"Введите название инструмента, например 'EURUSD'";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
                 }
               else if(chat.m_state==32)
                 {
                  chat.m_state=31;
                  string msg=(m_lang==LANGUAGE_EN)?"Select a timeframe like 'H1'":"Введите период графика, например 'H1'";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                 }
               else
                 {
                  chat.m_state=0;
                  string msg=(m_lang==LANGUAGE_EN)?"Choose a menu item":"Выберите пункт меню";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
                 }
               continue;
              }

            //---
            if(text=="/info" || text=="Account Info" || text=="Информация")
              {
               chat.m_state=1;
               string currency=AccountInfoString(ACCOUNT_CURRENCY);
               string msg=StringFormat("%d: %s\n",AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER));
               msg+=StringFormat("%s: %.2f %s\n",(m_lang==LANGUAGE_EN)?"Balance":"Баланс",AccountInfoDouble(ACCOUNT_BALANCE),currency);
               msg+=StringFormat("%s: %.2f %s\n",(m_lang==LANGUAGE_EN)?"Profit":"Прибыль",AccountInfoDouble(ACCOUNT_PROFIT),currency);
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
              }

            //---
            if(text=="/quotes" || text=="Quotes" || text=="Котировки")
              {
               chat.m_state=2;
               string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like 'EURUSD'":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }

            //---  
            if(text=="/charts" || text=="Charts" || text=="Графики")
              {
               chat.m_state=3;
               string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like 'EURUSD'":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }

            //---  
            if(text=="/ordini" || text=="Ordini" || text=="Графики")
              {
               chat.m_state=4;
               string msg=(m_lang==LANGUAGE_EN)?"Gestione Trading System":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_TS,false,false));
              }

            //---  
            if(text=="/altro" || text=="Altro..." || text=="Графики")
              {
               chat.m_state=5;
               string msg=(m_lang==LANGUAGE_EN)?"Scegli un'opzione":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_ALTRO,false,false));
              }

            //--- Quotes  
            if(chat.m_state==2)
              {
               string mask=(m_lang==LANGUAGE_EN)?"Invalid symbol name '%s'":"Инструмент '%s' не найден";
               string msg=StringFormat(mask,text);
               StringToUpper(text);
               string symbol=text;
               if(SymbolSelect(symbol,true))
                 {
                  double open[1]={0};

                  m_symbol=symbol;
                  //--- upload history
                  for(int k=0;k<3;k++)
                    {
#ifdef __MQL4__
                     double array[][6];
                     ArrayCopyRates(array,symbol,PERIOD_D1);
#endif

                     Sleep(2000);
                     CopyOpen(symbol,PERIOD_D1,0,1,open);
                     if(open[0]>0.0)
                        break;
                    }

                  int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
                  double bid=SymbolInfoDouble(symbol,SYMBOL_BID);

                  CopyOpen(symbol,PERIOD_D1,0,1,open);
                  if(open[0]>0.0)
                    {
                     double percent=100*(bid-open[0])/open[0];
                     //--- sign
                     string sign=ShortToString(0x25B2);
                     if(percent<0.0)
                        sign=ShortToString(0x25BC);

                     msg=StringFormat("%s: %s %s (%s%%)",symbol,DoubleToString(bid,digits),sign,DoubleToString(percent,2));
                    }
                  else
                    {
                     msg=(m_lang==LANGUAGE_EN)?"No history for ":"Нет истории для "+symbol;
                    }
                 }

               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }

            //--- Charts
            if(chat.m_state==3)
              {

               StringToUpper(text);
               string symbol=text;
               if(SymbolSelect(symbol,true))
                 {
                  m_symbol=symbol;

                  chat.m_state=31;
                  string msg=(m_lang==LANGUAGE_EN)?"Select a timeframe like 'H1'":"Введите период графика, например 'H1'";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                 }
               else
                 {
                  string mask=(m_lang==LANGUAGE_EN)?"Invalid symbol name '%s'":"Инструмент '%s' не найден";
                  string msg=StringFormat(mask,text);
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
                 }
               continue;
              }

            //Charts->Periods
            if(chat.m_state==31)
              {
               bool found=false;
               int total=ArraySize(_periods);
               for(int k=0; k<total; k++)
                 {
                  string str_tf=StringSubstr(EnumToString(_periods[k]),7);
                  if(StringCompare(str_tf,text,false)==0)
                    {
                     m_period=_periods[k];
                     found=true;
                     break;
                    }
                 }

               if(found)
                 {
                  //--- template
                  chat.m_state=32;
                  string str="[[\""+EMOJI_BACK+"\",\""+EMOJI_TOP+"\"]";
                  str+=",[\"None\"]";
                  for(int k=0;k<m_templates.Total();k++)
                     str+=",[\""+m_templates.At(k)+"\"]";
                  str+="]";

                  SendMessage(chat.m_id,(m_lang==LANGUAGE_EN)?"Select a template":"Выберите шаблон",ReplyKeyboardMarkup(str,false,false));
                 }
               else
                 {
                  SendMessage(chat.m_id,(m_lang==LANGUAGE_EN)?"Invalid timeframe":"Неправильно задан период графика",ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                 }
               continue;
              }
            //---
            if(chat.m_state==32)
              {
               m_template=text;
               if(m_template=="None")
                  m_template="standard";
               int result=SendScreenShot(chat.m_id,m_symbol,m_period,m_template);
               if(result!=0)
                  Print(GetErrorDescription(result,InpLanguage));
              }

            //--- Ordini
            if(chat.m_state==4)
              {
               double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
               double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
               
               //--- Inserisci Ordine
               if(text=="SELL")
                  {
                  trade.Sell(LotsToBuy,NULL,Bid,NULL,NULL,NULL);
                  Print("Inviato ordine di SELL");
                  int result=SendScreenShot(chat.m_id,m_symbol,m_period,"standard");
                  if(result!=0)
                     Print(GetErrorDescription(result,InpLanguage));
                  }
               
               if(text=="BUY")
                  {
                  trade.Buy(LotsToBuy,NULL,Ask,NULL,NULL,NULL);
                  Print("Inviato ordine di BUY");
                  int result=SendScreenShot(chat.m_id,m_symbol,m_period,"standard");
                  if(result!=0)
                     Print(GetErrorDescription(result,InpLanguage));
                  }
               
               if(text=="Chiudi tutte le posizioni")
                  {
                  CloseAllPositions();
                  Print("Chiuse tutte le posizioni");
                  int result=SendScreenShot(chat.m_id,m_symbol,m_period,"standard");
                  if(result!=0)
                     Print(GetErrorDescription(result,InpLanguage));
                  SendMessage(chat.m_id,"Chiuse tutte le posizioni");
                  }
                            
               //--- Unmute
               if(text==LOCK_CODE+" "+LOCK_TEXT)
                 {
                  m_lock_state=false;
                  string kyb = "[[\""+EMOJI_TOP+"\",\""+EMOJI_BACK+"\"],[\"SELL\",\"BUY\"],[\"Chiudi tutte le posizioni\"],[\"\xF513 Unlock\"]]";
                  bot.SendMessage(chat.m_id,UNLOCK_TEXT,bot.ReplyKeyboardMarkup(kyb,false,false));
                 }
   
               //--- Mute
               if(text==UNLOCK_CODE+" "+UNLOCK_TEXT)
                 {
                  m_lock_state=true;
                  string kyb = "[[\""+EMOJI_TOP+"\",\""+EMOJI_BACK+"\"],[\"SELL\",\"BUY\"],[\"Chiudi tutte le posizioni\"],[\"\xF512 Lock\"]]";
                  bot.SendMessage(chat.m_id,LOCK_TEXT,bot.ReplyKeyboardMarkup(kyb,false,false));
                 }
               continue;
              }

            //--- Altro...
            if(chat.m_state==5)
              {
               
               //--- Inserisci Ordine
               if(text=="Kill TS")
               {
                  string msg = "Inviato ordine di stoppare il TS";
                  Print(msg);
                  int result = bot.SendMessage(chat.m_id,msg);
                  if(result!=0)
                     Print(GetErrorDescription(result,InpLanguage));
                     
                  ExpertRemove();
               }
               continue;
              }
           }
        }         
     }
  };

//+------------------------------------------------------------------+
#define EXPERT_NAME     "Telegram Bot"
#define EXPERT_VERSION  "1.00"
#property version       EXPERT_VERSION
#define CAPTION_COLOR   clrWhite
#define LOSS_COLOR      clrOrangeRed

//+------------------------------------------------------------------+
//|   Input parameters                                               |
//+------------------------------------------------------------------+
input ENUM_LANGUAGES    InpLanguage=LANGUAGE_EN;//Language
input ENUM_UPDATE_MODE  InpUpdateMode=UPDATE_NORMAL;//Update Mode
input string            InpToken="871454864:AAGKLdMR0SI_lqSeYkAiHlBnkUqhLfAXYKs";//Token
input string            InpUserNameFilter="";//Whitelist Usernames
input string            InpTemplates="ADX;BollingerBands;Momentum;CCI;Migliorino";//Templates

//---
CComment       comment;
CMyBot         bot;
ENUM_RUN_MODE  run_mode;
datetime       time_check;
int            web_error;
int            init_error;
string         photo_id=NULL;
//+------------------------------------------------------------------+
//|   OnInit                                                         |
//+------------------------------------------------------------------+
int OnInit()
  {
  
  //SendNotification("TS Avviato");
  
//--- DAVIDE:

   //Definizione indicaotri Bande di Migliorino
   
   Print(_Period);
   
   int PeriodMigl1 = 768;        //Migliorino1 - periodo di riferimento
   double PercMigl1 = 0.5;       //Migliorino1 - % banda
   int PeriodMigl2 = 384;        //Migliorino2 - periodo di riferimento
   double PercMigl2 = 0.4;       //Migliorino2 - % banda
   int PeriodMigl3 = 194;        //Migliorino3 - periodo di riferimento
   double PercMigl3 = 0.2;       //Migliorino3 - % banda   
    
   switch (_Period)
      {
         case 15:
             PeriodMigl1 = 768;        //Migliorino1 - periodo di riferimento
             PercMigl1 = 0.5;       //Migliorino1 - % banda
             PeriodMigl2 = 384;        //Migliorino2 - periodo di riferimento
             PercMigl2 = 0.4;       //Migliorino2 - % banda
             PeriodMigl3 = 194;        //Migliorino3 - periodo di riferimento
             PercMigl3 = 0.2;       //Migliorino3 - % banda
            break;
         case 30:
             PeriodMigl1 = 768/2;        //Migliorino1 - periodo di riferimento
             PercMigl1 = 0.5;       //Migliorino1 - % banda
             PeriodMigl2 = 384/2;        //Migliorino2 - periodo di riferimento
             PercMigl2 = 0.4;       //Migliorino2 - % banda
             PeriodMigl3 = 194/2;        //Migliorino3 - periodo di riferimento
             PercMigl3 = 0.2;       //Migliorino3 - % banda
            break;
         case 16385:
             PeriodMigl1 = 768/4;        //Migliorino1 - periodo di riferimento
             PercMigl1 = 0.5;       //Migliorino1 - % banda
             PeriodMigl2 = 384/4;        //Migliorino2 - periodo di riferimento
             PercMigl2 = 0.4;       //Migliorino2 - % banda
             PeriodMigl3 = 194/4;        //Migliorino3 - periodo di riferimento
             PercMigl3 = 0.2;       //Migliorino3 - % banda
            break;
         case 16388:
             PeriodMigl1 = 768/16;        //Migliorino1 - periodo di riferimento
             PercMigl1 = 0.5;       //Migliorino1 - % banda
             PeriodMigl2 = 384/16;        //Migliorino2 - periodo di riferimento
             PercMigl2 = 0.4;       //Migliorino2 - % banda
             PeriodMigl3 = 194/16;        //Migliorino3 - periodo di riferimento
             PercMigl3 = 0.2;       //Migliorino3 - % banda
            break;
         
      }

   Print(EnumToString(_Period));
   
   MIGL1definition=iCustom(_Symbol,_Period,"Migliorino_Bands",PeriodMigl1,PercMigl1,clrYellow,PRICE_CLOSE);
   MIGL2definition=iCustom(_Symbol,_Period,"Migliorino_Bands",PeriodMigl2,PercMigl2,clrRed,PRICE_CLOSE);
   MIGL3definition=iCustom(_Symbol,_Period,"Migliorino_Bands",PeriodMigl3,PercMigl3,clrGreen,PRICE_CLOSE);
      
   //--- now make an attempt resulting in error
   if(!ChartIndicatorAdd(0,0,MIGL1definition))
      PrintFormat("Failed to add MIGLIORINO1 indicator on %d chart window. Error code  %d",0,GetLastError());
   if(!ChartIndicatorAdd(0,0,MIGL2definition))
      PrintFormat("Failed to add MIGLIORINO2 indicator on %d chart window. Error code  %d",0,GetLastError());
   if(!ChartIndicatorAdd(0,0,MIGL3definition))
      PrintFormat("Failed to add MIGLIORINO3 indicator on %d chart window. Error code  %d",0,GetLastError());  

//---
   run_mode=GetRunMode();

//--- stop working in tester
   if(run_mode!=RUN_LIVE)
     {
      PrintError(ERR_RUN_LIMITATION,InpLanguage);
      return(INIT_FAILED);
     }

   int y=40;
   if(ChartGetInteger(0,CHART_SHOW_ONE_CLICK))
      y=120;
   comment.Create("myPanel",20,y);
   comment.SetColor(clrDimGray,clrBlack,220);
//--- set language
   bot.Language(InpLanguage);

//--- set token
   init_error=bot.Token(InpToken);

//--- set filter
   bot.UserNameFilter(InpUserNameFilter);

//--- set templates
   bot.Templates(InpTemplates);

//--- set timer
   int timer_ms=3000;
   switch(InpUpdateMode)
     {
      case UPDATE_FAST:    timer_ms=1000; break;
      case UPDATE_NORMAL:  timer_ms=2000; break;
      case UPDATE_SLOW:    timer_ms=3000; break;
      default:             timer_ms=3000; break;
     };
   EventSetMillisecondTimer(timer_ms);
   OnTimer();
   
//--- Comunicazioni
   if (use_Telegram)
      bot.SendMessage(chat_ID,StringFormat("TS avviato (Versione: %s), ecco la situazione attuale (%s):",VERSION,StringSubstr(EnumToString(_Period),7)));
   if (use_Telegram)
      bot.SendMessage(chat_ID,StringFormat("Motivo dell'aggiornamento (%s):",desc_agg));
   int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
   if(result!=0)
      Print(GetErrorDescription(result,InpLanguage));
//--- done
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//|   OnDeinit                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   int n=ChartIndicatorsTotal(0,0);
   ChartIndicatorDelete(0,0,ChartIndicatorName(0,0,1));
   IndicatorRelease(MIGL1definition);
   ChartIndicatorDelete(0,0,ChartIndicatorName(0,0,2));
   IndicatorRelease(MIGL2definition);
   ChartIndicatorDelete(0,0,ChartIndicatorName(0,0,3));
   IndicatorRelease(MIGL3definition);
//---
   if(reason==REASON_CLOSE ||
      reason==REASON_PROGRAM ||
      reason==REASON_PARAMETERS ||
      reason==REASON_REMOVE ||
      reason==REASON_RECOMPILE ||
      reason==REASON_ACCOUNT ||
      reason==REASON_INITFAILED)
     {
      time_check=0;
      comment.Destroy();
     }
//---
   EventKillTimer();
   ChartRedraw();
   if (use_Telegram)
      bot.SendMessage(chat_ID,StringFormat("TS stoppato (%s):",getUninitReasonText(UninitializeReason())));
   //SendNotification("TS OnDeinit");
  }
//+------------------------------------------------------------------+
//|   OnChartEvent                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   comment.OnChartEvent(id,lparam,dparam,sparam);
  }
//+------------------------------------------------------------------+
//|   OnTimer                                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {

//--- show init error
   if(init_error!=0)
     {
      //--- show error on display
      CustomInfo info;
      GetCustomInfo(info,init_error,InpLanguage);

      //---
      comment.Clear();
      comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);
      comment.SetText(1,info.text1, LOSS_COLOR);
      if(info.text2!="")
         comment.SetText(2,info.text2,LOSS_COLOR);
      comment.Show();

      return;
     }

//--- show web error
   if(run_mode==RUN_LIVE)
     {

      //--- check bot registration
      if(time_check<TimeLocal()-PeriodSeconds(PERIOD_H1))
        {
         time_check=TimeLocal();
         if(TerminalInfoInteger(TERMINAL_CONNECTED))
           {
            //---
            web_error=bot.GetMe();
            if(web_error!=0)
              {
               //---
               if(web_error==ERR_NOT_ACTIVE)
                 {
                  time_check=TimeCurrent()-PeriodSeconds(PERIOD_H1)+300;
                 }
               //---
               else
                 {
                  time_check=TimeCurrent()-PeriodSeconds(PERIOD_H1)+5;
                 }
              }
           }
         else
           {
            web_error=ERR_NOT_CONNECTED;
            time_check=0;
           }
        }

      //--- show error
      if(web_error!=0)
        {
         comment.Clear();
         comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);

         if(
            #ifdef __MQL4__ web_error==ERR_FUNCTION_NOT_CONFIRMED #endif
            #ifdef __MQL5__ web_error==ERR_FUNCTION_NOT_ALLOWED #endif
            )
           {
            time_check=0;

            CustomInfo info={0};
            GetCustomInfo(info,web_error,InpLanguage);
            comment.SetText(1,info.text1 ,LOSS_COLOR);
            comment.SetText(2,info.text2,LOSS_COLOR);
           }
         else
            comment.SetText(1,GetErrorDescription(web_error,InpLanguage),LOSS_COLOR);

         comment.Show();
         return;
        }
     }

//---
   bot.GetUpdates();

//---
   if(run_mode==RUN_LIVE)
     {
      comment.Clear();
      comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);
      comment.SetText(1,StringFormat("%s: %s",(InpLanguage==LANGUAGE_EN)?"Bot Name":"Имя Бота",bot.Name()),CAPTION_COLOR);
      comment.SetText(2,StringFormat("%s: %d",(InpLanguage==LANGUAGE_EN)?"Chats":"Чаты",bot.ChatsTotal()),CAPTION_COLOR);
      comment.Show();
     }

//---
   bot.ProcessMessages();
  }
  
//+------------------------------------------------------------------+
//|   OnTick                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {

   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
   
   MqlRates PriceInfo[];
   int PriceData = CopyRates(_Symbol,_Period,0,Dim+1,PriceInfo);

   double upperMIGL1array[];
   double lowerMIGL1array[];
   CopyBuffer(MIGL1definition,0,0,Dim+1,upperMIGL1array);
   CopyBuffer(MIGL1definition,1,0,Dim+1,lowerMIGL1array);
   double upperMIGL2array[];
   double lowerMIGL2array[];
   CopyBuffer(MIGL2definition,0,0,Dim+1,upperMIGL2array);
   CopyBuffer(MIGL2definition,1,0,Dim+1,lowerMIGL2array);
   double upperMIGL3array[];
   double lowerMIGL3array[];
   CopyBuffer(MIGL3definition,0,0,Dim+1,upperMIGL3array);
   CopyBuffer(MIGL3definition,1,0,Dim+1,lowerMIGL3array);
   
   NewBar();
   
//CONDITIONS TO ENTER

   string order_in = "";         //ordine di ingresso
   
   bool req_in_long = true;      //variabile che rimane true finché non viene invalidata da qualche filtro long
   bool req_in_short = true;     //variabile che rimane true finché non viene invalidata da qualche filtro short
   
   if (MIGL_in == true)
   {
    //verifica se il prezzo è inferiore a tutte 3 le bande inferiori di Migliorino1 nell'ultima candela chiusa
    if (PriceInfo[Dim-1].close < lowerMIGL1array[Dim-1] && PriceInfo[Dim-1].close < lowerMIGL2array[Dim-1] && PriceInfo[Dim-1].close < lowerMIGL3array[Dim-1])
       {signal_crossed_down = true;
        time_to_call = TimeCurrent()+bars_count*_Period*60;}
    //verifica se la banda veloce è inferiore alla banda media e contemporaneamente la banda media è inferiore alla banda lenta nell'ultima candela chiusa
    if (lowerMIGL3array[Dim-1] < lowerMIGL2array[Dim-1] && lowerMIGL2array[Dim-1] < lowerMIGL1array[Dim-1])
       {bands_crossed_down = true;
        time_to_call = TimeCurrent()+bars_count*_Period*60;}

    //verifica se il prezzo è superiore a tutte 3 le bande superiori di Migliorino1 nell'ultima candela chiusa
    if (PriceInfo[Dim-1].close > upperMIGL1array[Dim-1] && PriceInfo[Dim-1].close > upperMIGL2array[Dim-1] && PriceInfo[Dim-1].close > upperMIGL3array[Dim-1])
       {signal_crossed_up = true;
        time_to_call = TimeCurrent()+bars_count*_Period*60;}
    //verifica se la banda veloce è superiore alla banda media e contemporaneamente la banda media è superiore alla banda lenta nell'ultima candela chiusa
    if (upperMIGL3array[Dim-1] > upperMIGL2array[Dim-1] && upperMIGL2array[Dim-1] > upperMIGL1array[Dim-1])
       {bands_crossed_up = true;
        time_to_call = TimeCurrent()+bars_count*_Period*60;}

    if ((signal_crossed_down == true || bands_crossed_down == true) && TimeCurrent() >= time_to_call)
       {
       string msg="Ingresso long imminente";
       Print(msg);
       int res=bot.SendMessage(chat_ID,msg);
       int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
       if(result!=0)
         Print(GetErrorDescription(result,InpLanguage));
       time_to_call = TimeCurrent()+bars_count*_Period*60;}

    if ((signal_crossed_up == true || bands_crossed_up == true) && TimeCurrent() >= time_to_call)
       {
       string msg="Ingresso short imminente";
       Print(msg);
       int res=bot.SendMessage(chat_ID,msg);
       int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
       if(result!=0)
       Print(GetErrorDescription(result,InpLanguage));
       time_to_call = TimeCurrent()+bars_count*_Period*60;}

    //verifica se, una volta che il pezzo ha oltrepassato le 3 bande inferiori, esso rientra oltrepassandone una; oppure se, una volta che le bande si sono incrociate al ribasso, una di esse rientra incrociando di nuovo
    if ((signal_crossed_down == true && (PriceInfo[Dim-1].close > lowerMIGL1array[Dim-1] || PriceInfo[Dim-1].close > lowerMIGL2array[Dim-1] || PriceInfo[Dim-1].close > lowerMIGL2array[Dim-1])) ||
       (bands_crossed_down == true && (lowerMIGL3array[Dim-1] > lowerMIGL2array[Dim-1] || lowerMIGL2array[Dim-1] > lowerMIGL1array[Dim-1])))
       {req_in_short = false;}
    //verifica se, una volta che il pezzo ha oltrepassato le 3 bande supeeriori, esso rientra oltrepassandone una; oppure se, una volta che le bande si sono incrociate al rialzo, una di esse rientra incrociando di nuovo       
    else if ((signal_crossed_up == true && (PriceInfo[Dim-1].close < upperMIGL1array[Dim-1] || PriceInfo[Dim-1].close < upperMIGL2array[Dim-1] || PriceInfo[Dim-1].close < upperMIGL2array[Dim-1])) ||
       (bands_crossed_up == true && (upperMIGL3array[Dim-1] < upperMIGL2array[Dim-1] || upperMIGL2array[Dim-1] < upperMIGL1array[Dim-1])))
       {req_in_long = false;}
    else
       {req_in_short = false;
       req_in_long = false;}
    
    //una volta che le condizioni per emettere l'ordine sono verificate, si azzerano le variabili di attraversamento
    if (req_in_short == true || req_in_long == true)
       {signal_crossed_down = false;
       signal_crossed_up = false;
       bands_crossed_down = false;
       bands_crossed_up = false;}
   }

//OPENING ORDERS

   //se vengono rispettati tutti i filtri e se non ci sono altre posizioni o ordini aperti e se siamo all'inizio di una nuova candela
   if (req_in_long == true && PositionsTotal()<1 && OrdersTotal()<1 && new_bar == true)   
   //allora compra
   {
   order_in = "buyOrder";
   }

   //se vengono rispettati tutti i filtri e se non ci sono altre posizioni o ordini aperti e se siamo all'inizio di una nuova candela
   if (req_in_short == true && PositionsTotal()<1 && OrdersTotal()<1 && new_bar == true)
   {
   //allora vendi
   order_in = "sellOrder";
   }

//OPENING POSITIONS

   //DebugBreak();
   //order_in = "buyOrder";     //ADDED!!!!!!!!!!!!!!
   //contatore++;               //ADDED!!!!!!!!!!!!!!

   //se c'è un ordine di comprare
   if (order_in == "buyOrder")
   {
    string msg=StringFormat("MIGLIORINO Signal \xF4E3\nSymbol: %s\nTimeframe: %s\nType: Buy\nPrice: %s\nTime: %s",
    _Symbol,
    StringSubstr(EnumToString(_Period),7),
    DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits),
    TimeToString(iTime(_Symbol,_Period,0)));
    int res=bot.SendMessage(chat_ID,msg);
    if(res!=0)
    Print("Error: ",GetErrorDescription(res));

    //compra
    trade.Buy(LotsToBuy,NULL,Ask,NULL,NULL,NULL);
    int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
       if(result!=0)
         Print(GetErrorDescription(result,InpLanguage));
    position = "longPosition";
   }
   
   //se c'è un ordine di vendere
   if (order_in == "sellOrder")
   {
    //vendi
    trade.Sell(LotsToBuy,NULL,Bid,NULL,NULL,NULL);
    int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
       if(result!=0)
         Print(GetErrorDescription(result,InpLanguage));
    position = "shortPosition";
    
    string msg=StringFormat("MIGLIORINO Signal \xF4E3\nSymbol: %s\nTimeframe: %s\nType: Sell\nPrice: %s\nTime: %s",
    _Symbol,
    StringSubstr(EnumToString(_Period),7),
    DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits),
    TimeToString(iTime(_Symbol,_Period,0)));
    int res=bot.SendMessage(chat_ID,msg);
    if(res!=0)
    Print("Error: ",GetErrorDescription(res));
   }

//CONDITIONS TO EXIT

   string order_out = "";        //ordine di uscita
   
   bool req_out_long = true;     //variabile che rimane true finché non viene invalidata da qualche filtro long
   bool req_out_short = true;    //variabile che rimane true finché non viene invalidata da qualche filtro short

   if (MIGL_out == true)
   {
    //verifica se il prezzo è inferiore alla banda inferiore di Migliorino3 nell'ultima candela chiusa
    if (PriceInfo[Dim-1].close < lowerMIGL3array[Dim-1])
    {req_out_short = false;}
    //verifica se il prezzo è superiore alla banda superiore di Migliorino3 nell'ultima candela chiusa
    else if (PriceInfo[Dim-1].close > upperMIGL3array[Dim-1])
    {req_out_long = false;}
    else
    {req_out_long = false;
    req_out_short = false;}
   }
   
//CLOSING ORDERS

   //if (contatore == 10000)       //ADDED!!!!!!!!!!!!!!
   //{order_out = "buyCloseOrder"; //ADDED!!!!!!!!!!!!!!
   // contatore=0;}                //ADDED!!!!!!!!!!!!!!
 
   //se vengono rispettati tutti i filtri e se c'è una posizione aperta e se siamo all'inizio di una nuova candela
   if (req_out_long == true && position == "shortPosition" && new_bar == true)   
   //allora chiudi l'ordine sell
   {
   order_out = "sellCloseOrder";
   }

   //se vengono rispettati tutti i filtri e se c'è una posizione aperta e se siamo all'inizio di una nuova candela
   if (req_out_short == true && position == "longPosition" && new_bar == true)
   {
   //allora chiudi l'ordine buy
   order_out = "buyCloseOrder";
   }

//CLOSING POSITIONS

   //se c'è un ordine di vendere (chiudendo una posizione long) o comprare (chiudendo una posizione short)
   if (order_out == "sellCloseOrder" || order_out == "buyCloseOrder")
   {
    CloseAllPositions();
    int result=bot.SendScreenShot(chat_ID,_Symbol,_Period,"standard");
       if(result!=0)
         Print(GetErrorDescription(result,InpLanguage));
   }

//OUTPUTS ON CHARTS

   int Balance = int(AccountInfoDouble(ACCOUNT_BALANCE));
   
   if (Balance >= Balance_max)
   {Balance_max = Balance;}
   
   if (Balance_max-Balance > DD_max)
   {DD_max = Balance_max-Balance;}

   Comment("\n"+
           "Balance: "+DoubleToString(Balance)+"\n"+
           "\n"+
           "order_in: "+order_in+"\n"+
           "order_out: "+order_out+"\n"+
           "\n"+
           "PositionsTotal: "+IntegerToString(PositionsTotal())+"\n"+
           "Position: "+position+"\n"+
           "\n"+
           "req_in_long: "+IntegerToString(req_in_long)+"\n"+
           "req_in_short: "+IntegerToString(req_in_short)+"\n"+
           "req_out_long: "+IntegerToString(req_out_long)+"\n"+
           "req_out_short: "+IntegerToString(req_out_short)+"\n"+
           "\n"+
           "upperMIGL1array: "+DoubleToString(upperMIGL1array[Dim-1])+"\n"+
           "PriceInfoClose: "+DoubleToString(PriceInfo[Dim-1].close)+"\n"+
           "lowerMIGL1array: "+DoubleToString(lowerMIGL1array[Dim-1])+"\n");
  }  
  
//+------------------------------------------------------------------+
//|   GetCustomInfo                                                  |
//+------------------------------------------------------------------+
void GetCustomInfo(CustomInfo &info,
                   const int _error_code,
                   const ENUM_LANGUAGES _lang)
  {
//--- функция для сообещний пользователей
   switch(_error_code)
     {
#ifdef __MQL5__
      case ERR_FUNCTION_NOT_ALLOWED:
         info.text1 = (_lang==LANGUAGE_EN)?"The URL does not allowed for WebRequest":"Этого URL нет в списке для WebRequest.";
         info.text2 = TELEGRAM_BASE_URL;
         break;
#endif
#ifdef __MQL4__
      case ERR_FUNCTION_NOT_CONFIRMED:
         info.text1 = (_lang==LANGUAGE_EN)?"The URL does not allowed for WebRequest":"Этого URL нет в списке для WebRequest.";
         info.text2 = TELEGRAM_BASE_URL;
         break;
#endif            

      case ERR_TOKEN_ISEMPTY:
         info.text1 = (_lang==LANGUAGE_EN)?"The 'Token' parameter is empty.":"Параметр 'Token' пуст.";
         info.text2 = (_lang==LANGUAGE_EN)?"Please fill this parameter.":"Пожалуйста задайте значение для этого параметра.";
         break;
     }

  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   CloseAllPositions                                              |
//+------------------------------------------------------------------+
//chiude tutte le posizioni aperte
void CloseAllPositions()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      int ticket = int(PositionGetTicket(i));
      trade.PositionClose(ticket);
      
      bot.SendMessage(chat_ID,"Chiusura di tutte le posizioni in corso");
   }
  }
//+------------------------------------------------------------------+
//|   NewBar                                                         |
//+------------------------------------------------------------------+  
  //verifica se siamo in una nuova candela: viene chiamata ad ogni tick e se il tick fa parte di una nuova candela allora new_time = true, altrimenti new_time = false
void NewBar()
  {
   static datetime new_time = 0;
   new_bar = false;
   if(new_time != iTime(_Symbol,_Period,0))
   {
    new_time = iTime(_Symbol,_Period,0);
    new_bar = true;
    bars++;
   }
  }
  
//+------------------------------------------------------------------+ 
//| getUninitReasonText                                              |
//+------------------------------------------------------------------+ 
string getUninitReasonText(int reasonCode) 
  { 
   string text=""; 
//--- 
   switch(reasonCode) 
     { 
      case REASON_ACCOUNT: 
         text="L'account è cambiato";break; 
      case REASON_CHARTCHANGE: 
         text="Il simbolo o timeframe sono cambiati";break; 
      case REASON_CHARTCLOSE: 
         text="Il chart Chart è stato chiuso";break; 
      case REASON_PARAMETERS: 
         text="I parametri di Input sono stati cambiati";break; 
      case REASON_RECOMPILE: 
         text="il programma "+__FILE__+" è stato ricompilato";break; 
      case REASON_REMOVE: 
         text="il programma "+__FILE__+" è stato rimosso dal chart";break; 
      case REASON_TEMPLATE: 
         text="Il nuovo template è stato applicato al chart";break; 
      default:text="Altra motivazione"; 
     } 
//--- 
   return text; 
  }
