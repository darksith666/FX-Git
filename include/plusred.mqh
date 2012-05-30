//|-----------------------------------------------------------------------------------------|
//|                                                                             PlusRed.mqh |
//|                                                             Copyright  2012, Dennis Lee |
//| Assert History                                                                          |
//| 1.10    Created functions OrderManagerBasket, OrderModifyBasket, CalcBreakEvenBasket,   |
//|            IsOkStopLossBasket and IsOkTakeProfitBasket.                                 |
//|            Added pending order array in LoadBuffers.                                    |
//|            Added user defined periods for Short and Long Cycle.                         |
//| 1.00    The PlusRed module is a martingale strategy comprising TWO baskets.             |
//|            The RedOrderManager() places subsequent orders for both baskets.             |
//|            Note that the first order is never placed by this module.                    |
//|            Created functions Init, LoadBuffer, ChildOrderSend, CycleGap, and Comment.   |
//|-----------------------------------------------------------------------------------------|
#property   copyright "Copyright  2012, Dennis Lee"

//|-----------------------------------------------------------------------------------------|
//|                           E X T E R N A L   V A R I A B L E S                           |
//|-----------------------------------------------------------------------------------------|
extern   double   RedBaseLot     =0.01;
extern   string   red_1          =" Mode 0-Use 1x only; BasketLevel <= 12";
extern   string   red_2          =" 1-Envy: 1,1,2,3,5,9,17,33,65,127,245,466";
extern   string   red_3          =" 2-Fibo: 1,1,2,3,5,8,13,21,34,55,89,144";
extern   int      RedMode        =0;
extern   int      RedBasketLevel =1;
extern   bool     RedShortCycle  =false;
extern   int      RedShortPeriod =PERIOD_M30;
extern   int      RedLongPeriod  =PERIOD_H4;
extern   bool     RedHardTP      =true;
extern   int      RedDebug       =1;
extern   int      RedDebugCount  =1000;

//|-----------------------------------------------------------------------------------------|
//|                           I N T E R N A L   V A R I A B L E S                           |
//|-----------------------------------------------------------------------------------------|
string   RedName="PlusRed";
string   RedVer="1.10";
//--- Assert variables for Basic
double   redSL;
int      redCycleSL=3;
int      red1Magic;
int      red2Magic;
//--- Assert variables for Opened Positions
int      redOpTicket[];
int      redOpType[];
double   redOpLots[];
double   redOpOpenPrice[];
double   redOpStopLoss[];
double   redOpTakeProfit[];
double   redOpProfit[];
string   redOpComment[];
//--- Assert variables for Pending Orders
int      redPoTicket[];
int      redPoType[];
double   redPoLots[];
double   redPoOpenPrice[];
double   redPoStopLoss[];
double   redPoTakeProfit[];
double   redPoProfit[];
string   redPoComment[];

//--- Assert variables for Martingale Mode
int      redMultiplier[];
//--- Assert variables to detect new bar
int      nextBarTime;
//--- Assert variables for cycle gaps
int      redCyclePip;
double   redBaseOpenPrice;
//--- Assert variables for debug
int      RedCount;

//|-----------------------------------------------------------------------------------------|
//|                             I N I T I A L I Z A T I O N                                 |
//|-----------------------------------------------------------------------------------------|
void RedInit(double SL, int mgc1, int mgc2)
{
//-- Assert Excel or SQL files are created.
//--- Assert Mode <= 2 and BasketLevel <= 12
   if( RedMode < 0 || RedMode > 2 )
   {
      Print("RedInit: Mode=",RedMode," is invalid. Set Mode=0");
      RedMode = 0;
   }
   if( RedBasketLevel > 12 )
   {
      Print("RedInit: BasketLevel exceeded maximum of 12. Set BasketLevel=12");
      RedBasketLevel = 12;
   }
//--- Initialize arrays
   ArrayResize(redMultiplier, 12);
//--- Populate arrays
//       0-Disabled: 1x for all levels
//       1-Envy: 1,1,2,3,5,9,17,33,65,127,245,466
//       2-Fibo: 1,1,2,3,5,8,13,21,34,55,89,144
   switch( RedMode )
   {
      case 0:
         for(int i=0; i<12; i++)
         {
            redMultiplier[i]=1;
         }
         break;
      case 1:
         redMultiplier[0]=1;
         redMultiplier[1]=1;
         redMultiplier[2]=2;
         redMultiplier[3]=3;
         redMultiplier[4]=5;
         redMultiplier[5]=9;
         redMultiplier[6]=17;
         redMultiplier[7]=33;
         redMultiplier[8]=65;
         redMultiplier[9]=127;
         redMultiplier[10]=245;
         redMultiplier[11]=466;
         break;
      case 2:
         redMultiplier[0]=1;
         redMultiplier[1]=1;
         redMultiplier[2]=2;
         redMultiplier[3]=3;
         redMultiplier[4]=5;
         redMultiplier[5]=8;
         redMultiplier[6]=13;
         redMultiplier[7]=21;
         redMultiplier[8]=34;
         redMultiplier[9]=55;
         redMultiplier[10]=89;
         redMultiplier[11]=144;
         break;
   }
//--- Initialize cycle gaps
   if( RedShortPeriod < 5 )
   {
      Print("RedInit: ShortPeriod below minimum of 5. Set ShortPeriod=5");
      RedShortPeriod = 5;
   }
   if( RedLongPeriod < 5 )
   {
      Print("RedInit: LongPeriod below minimum of 5. Set LongPeriod=5");
      RedLongPeriod = 5;
   }
   if( RedShortCycle )
      redCyclePip = RedCycleGap(60,Symbol(),RedShortPeriod);
   else
      redCyclePip = RedCycleGap(60,Symbol(),RedLongPeriod);
//--- Initialize stop loss and take profit
   if( SL < redCyclePip * redCycleSL )
   {
      redSL = redCyclePip * redCycleSL;
      Print("RedInit: SL is less than ",redCycleSL,"x CyclePip=",DoubleToStr(redCyclePip,0),". Set redSL=",DoubleToStr(redSL,0));
   }
   red1Magic = mgc1;
   red2Magic = mgc2;
}

//|-----------------------------------------------------------------------------------------|
//|                               M A I N   P R O C E D U R E                               |
//|-----------------------------------------------------------------------------------------|
void RedOrderManager()
{
   RedOrderManagerBasket(red1Magic, Symbol(), RedBasketLevel);
   RedOrderManagerBasket(red2Magic, Symbol(), RedBasketLevel);
}
void RedOrderManagerBasket(int mgc, string sym, int maxTrades)
{
   int    beg, end;
   int    oldTotal, newTotal;
   double drawdown;
   double calcSL, calcTP;
   double pts = MarketInfo( sym, MODE_POINT );
//--- Assert Load buffers with existing trades
   oldTotal = RedLoadBuffers(mgc,sym);
   if( oldTotal < 1 ) return(0);
//--- Assert calculate drawdown for child trade
   for(int j=0; j<oldTotal; j++)
   {
      drawdown = drawdown + redOpProfit[j];
   }
//--- Assert drawdown is always <= 0;
   drawdown=MathMin(drawdown,0);
   RedDebugPrint( 2,"RedOrderManagerBasket",
      RedDebugInt("mgc",mgc)+
      RedDebugStr("sym",sym)+
      RedDebugInt("maxTrades",maxTrades)+
      RedDebugDbl("drawdown",drawdown,2)+
      RedDebugDbl("buffer",redCyclePip*InitPts*RedBaseLot*TurtleBigValue(sym)/Point,2),
      false, 1 );
   
//--- Assert calculate SL and TP
   if( redOpType[end] == OP_BUY )
   {
      calcSL   = redOpOpenPrice[end] - redCycleSL * redCyclePip * InitPts;
      calcTP   = RedCalcBreakEvenBasket( OP_BUY, sym, drawdown - redCyclePip*InitPts*RedBaseLot*TurtleBigValue(sym)/Point );
      //calcTP   = calcTP + redCyclePip * InitPts;
   }
   if( redOpType[end] == OP_SELL )
   {
      calcSL   = redOpOpenPrice[end] + redCycleSL * redCyclePip * InitPts;
      calcTP   = RedCalcBreakEvenBasket( OP_SELL, sym, drawdown - redCyclePip*InitPts*RedBaseLot*TurtleBigValue(sym)/Point );
      //calcTP   = calcTP - redCyclePip * InitPts;
   }
   RedDebugPrint( 2,"RedOrderManagerBasket",
      RedDebugInt("end",end)+
      RedDebugInt("oldTotal",oldTotal)+
      RedDebugInt("type",redOpType[end])+
      RedDebugDbl("lots",redOpLots[end])+
      RedDebugDbl("OpenPrice",redOpOpenPrice[end],5)+
      RedDebugDbl("calcSL",calcSL,5)+
      RedDebugDbl("calcTP",calcTP,5),
      false, 1 );
//--- Assert Ok StopLoss basket
   beg = 0; end = oldTotal - 1;
   if( !RedIsOkStopLossBasket(calcSL) || !RedIsOkTakeProfitBasket(calcTP) )
   {
      RedOrderModifyBasket( mgc, sym, calcSL, calcTP, 0, maxTrades );
      oldTotal = RedLoadBuffers(mgc,sym);
   }
//--- Assert max Basket level has not been reached
   if( oldTotal >= RedBasketLevel ) return(0);
   
//--- Assert Check if child trade can be opened
   newTotal = RedChildOrderSend( mgc, sym, redSL, 0, maxTrades );
   if( newTotal == oldTotal ) return(0);
//--- Assert calculate Stop Loss for child trade
   beg = 0; end = newTotal - 1;
   calcSL = redOpStopLoss[end];
   calcTP = RedCalcBreakEvenBasket( redOpType[end], sym, drawdown );
   RedDebugPrint( 2,"RedOrderManagerBasket",
      RedDebugInt("end",end)+
      RedDebugInt("newTotal",newTotal)+
      RedDebugInt("type",redOpType[end])+
      RedDebugDbl("lots",redOpLots[end])+
      RedDebugDbl("OpenPrice",redOpOpenPrice[end],5)+
      RedDebugDbl("calcSL",calcSL,5)+
      RedDebugDbl("calcTP",calcTP,5),
      false, 1 );

//--- Assert Modify basket with calculated TP and SL
   RedOrderModifyBasket( mgc, sym, calcSL, calcTP, 0, maxTrades);

   return( calcTP );
}

//|-----------------------------------------------------------------------------------------|
//|                                 O R D E R   B U F F E R                                 |
//|-----------------------------------------------------------------------------------------|
int RedLoadBuffers(int mgc, string sym)
{
   int      totalOp;
   int      totalPo;
   int      type;
   double   lots;
   double   openPrice;
   double   SL;
   double   TP;
   double   profit;
   string   cmt;
   
   totalOp=EasyOrdersBasket(mgc,sym);
//--- Assert 7: Dynamically resize arrays for OrderSelect #1
   ArrayResize(redOpTicket,     totalOp);
   ArrayResize(redOpType,       totalOp);
   ArrayResize(redOpLots,       totalOp);
   ArrayResize(redOpOpenPrice,  totalOp);
   ArrayResize(redOpStopLoss,   totalOp);
   ArrayResize(redOpTakeProfit, totalOp);
   ArrayResize(redOpProfit,     totalOp);
   ArrayResize(redOpComment,    totalOp);
   
//--- Assert 1: Init OrderSelect #1
   int total=GhostOrdersTotal();
   int i, end;
   GhostInitSelect(true,0,SELECT_BY_POS,MODE_TRADES);
   for(int j=0; j<total; j++)
   {
      if( !GhostOrderSelect(j,SELECT_BY_POS,MODE_TRADES) ) break;
   //--- Assert 7: Populate arrays for OrderSelect #1
      if( GhostOrderMagicNumber()==mgc && GhostOrderSymbol()==sym )
      {
         redOpTicket[i]      =  GhostOrderTicket();
         redOpType[i]        =  GhostOrderType();
         redOpLots[i]        =  GhostOrderLots();
         redOpOpenPrice[i]   =  GhostOrderOpenPrice();
         redOpStopLoss[i]    =  GhostOrderStopLoss();
         redOpTakeProfit[i]  =  GhostOrderTakeProfit();
         redOpProfit[i]      =  GhostOrderProfit();
         redOpComment[i]     =  GhostOrderComment();
         i ++;
      }
   }
//--- Assert 1: Free OrderSelect #1
   GhostFreeSelect(false);
   end = totalOp - 1;
   if( totalOp > 0 ) RedDebugPrint( 2,"RedLoadBuffers",
      RedDebugInt("mgc",mgc)+
      RedDebugStr("sym",sym)+
      RedDebugInt("totalOp",totalOp)+
      RedDebugInt("end",end)+
      RedDebugInt("ticket",redOpTicket[end])+
      RedDebugInt("type",redOpType[end])+
      RedDebugDbl("lots",redOpLots[end])+
      RedDebugDbl("price",redOpOpenPrice[end],5)+
      RedDebugDbl("SL",redOpStopLoss[end],5)+
      RedDebugDbl("TP",redOpTakeProfit[end],5),
      false );
   
//--- Assert pending basket orders must not exceed basket level
   if( RedBasketLevel >= totalOp ) totalPo=RedBasketLevel-totalOp;
//--- Assert Dynamically resize arrays 
   ArrayResize(redPoTicket,     totalPo);
   ArrayResize(redPoType,       totalPo);
   ArrayResize(redPoLots,       totalPo);
   ArrayResize(redPoOpenPrice,  totalPo);
   ArrayResize(redPoStopLoss,   totalPo);
   ArrayResize(redPoTakeProfit, totalPo);
   ArrayResize(redPoProfit,     totalPo);
   ArrayResize(redPoComment,    totalPo);
//--- Assert if there is no parent order, then use dummy values
   if( totalOp == 0 )
   {
      type        = -1;
      lots        = RedBaseLot;
      openPrice   = 0;
      SL          = 0;
      TP          = 0;
      profit      = 0;
      cmt         = "";
   }
   else
   {
      type        = redOpType[0];
      lots        = RedBaseLot;
      openPrice   = redOpOpenPrice[totalOp-1];
      SL          = redOpStopLoss[0];
      TP          = redOpTakeProfit[0];
      cmt         = "";
   }
   
   for(i=0; i<totalPo; i++)
   {
      j = totalOp + i;
   //--- Assert Populate arrays
      redPoTicket[i]       = 0;
      redPoType[i]         = type;
      redPoLots[i]         = redMultiplier[j] * lots;
      redPoProfit[i]       = 0;
      redPoComment[i]      = "";
      if( type == OP_BUY )
      {
         redPoOpenPrice[i]    = openPrice - ( (i+1) * redCyclePip * InitPts );
         redPoStopLoss[i]     = redPoOpenPrice[i] - redCycleSL * redCyclePip * InitPts;
         redPoTakeProfit[i]   = redPoOpenPrice[i] + redCyclePip * InitPts;
      }
      if( type == OP_SELL )
      {
         redPoOpenPrice[i]    = openPrice + ( (i+1) * redCyclePip * InitPts );
         redPoStopLoss[i]     = redPoOpenPrice[i] + redCycleSL * redCyclePip * InitPts;
         redPoTakeProfit[i]   = redPoOpenPrice[i] - redCyclePip * InitPts;
      }
   }
   if( totalPo > 0 ) RedDebugPrint( 2,"RedLoadBuffers",
      RedDebugInt("mgc",mgc)+
      RedDebugStr("sym",sym)+
      RedDebugInt("totalPo",totalPo)+
      RedDebugInt("beg",0)+
      RedDebugInt("ticket",redPoTicket[0])+
      RedDebugInt("type",redPoType[0])+
      RedDebugDbl("lots",redPoLots[0])+
      RedDebugDbl("price",redPoOpenPrice[0],5)+
      RedDebugDbl("SL",redPoStopLoss[0],5)+
      RedDebugDbl("TP",redPoTakeProfit[0],5),
      true );
   
   return( totalOp );
}
double RedCalcBreakEvenBasket(int type, string sym, double dd)
{
   double   val;
   double   lots;
   int      totalOp;
   double   pts = MarketInfo( sym, MODE_POINT );
   
   totalOp=ArraySize(redOpTicket);
   for(int j=0; j<totalOp; j++)
   {
      lots = lots + redOpLots[j];
      
      if( type == OP_BUY )
      {
      //--- Assert calculate profits
      //       -dd = (closePrice-openPrice)*lots*TurtleBigValue(sym)/pts;
      //       -dd = (close-op1)*lot1*T/p + (close-op2)*lot2*T/p
      //       -dd*p/T = close*lot1 - op1*lot1 + close*lot2 - op2*lot2
      //       -dd*p/T = close(lot1 + lot2) - op1*lot1 - op2*lot2
      //       close(lot1 + lot2) = -dd*p/T + op1*lot1 + op2*lot2
      //       close = ( -dd*p/T + op1*lot1 + op2*lot2 ) / ( lot1 + lot2 )
         val = val + redOpOpenPrice[j] * redOpLots[j];
      }
      if( type == OP_SELL )
      {
      //--- Assert calculate profits
      //       calcProfit = (openPrice-closePrice)*lots*TurtleBigValue(sym)/pts;
      //       -dd = (op1-close)*lot1*T/p + (op2-close)*lot2*T/p
      //       -dd*p/T = op1*lot1 - close*lot1 + op2*lot2 - close*lot2
      //       -dd*p/T = op1*lot1 + op2*lot2 - close(lot1 + lot2)
      //       close(lot1 + lot2) = op1*lot1 + op2*lot2 + dd*p/T
      //       close = ( dd*p/T + op1*lot1 + op2*lot2 ) / ( lot1 + lot2 )
         val = val + redOpOpenPrice[j] * redOpLots[j];
      }
   }
   if( type == OP_BUY )
      val = ( val - dd*pts/TurtleBigValue(sym) ) / lots;
   if( type == OP_SELL )
      val = ( val + dd*pts/TurtleBigValue(sym) ) / lots;
      
   return(val);
}
bool RedIsOkStopLossBasket(double SL)
{
   bool  aOk=true;
   int   totalOp;
   totalOp=ArraySize(redOpTicket);
   for(int j=0; j<totalOp; j++)
   {
      if( redOpStopLoss[j] == 0 )
      {
         aOk = false;
         break;
      }
      else if( SL != 0 && redOpStopLoss[j] != SL )
      {
         aOk = false;
         break;
      }
   }
   return( aOk );
}
bool RedIsOkTakeProfitBasket(double TP)
{
   bool     aOk=true;
   int      totalOp;
   double   gapTP;
   if( RedHardTP )
   {
      totalOp=ArraySize(redOpTicket);
      for(int j=0; j<totalOp; j++)
      {
         if( redOpTakeProfit[j] == 0 )
         {
            aOk = false;
            break;
         }
         else if( TP != 0 && redOpTakeProfit[j] > TP )
         {
            aOk = false;
            break;
         }
      }
   }
   return( aOk );
}
//+-----------------------------------------------------------------------------------------|
//|                             O P E N   C H I L D   T R A D E S                           |
//+-----------------------------------------------------------------------------------------|
int RedChildOrderSend(int mgc, string sym, double SL, double TP, int maxTrades)
{
   int ticket=-1;
   int total=ArraySize(redOpTicket);
   int newLevel=total;
//--- Assert optimize function check total > 0
   if( total <= 0 ) return(0);
//--- Assert optimize function check pending orders > 0
   if( ArraySize(redPoTicket) <= 0 ) return(0);
//--- Assert copy values to child order   
   double   curPrice;
//--- Assert populate values for child order
   if( redPoType[0] == OP_BUY )
   {
      curPrice = MarketInfo( sym, MODE_ASK );
      if( curPrice <= redPoOpenPrice[0] )
         ticket=EasyOrderBuy( mgc, sym, redPoLots[0], 0, 0, redPoComment[0] );
   }
   if( redPoType[0] == OP_SELL )
   {
      curPrice = MarketInfo( sym, MODE_BID );
      if( curPrice >= redPoOpenPrice[0] )
         ticket=EasyOrderBuy( mgc, sym, redPoLots[0], 0, 0, redPoComment[0] );
   }
   if( ticket > 0 ) 
   {
      RedOrderModifyBasket( mgc, sym, redPoStopLoss[0], 0, 0, maxTrades );
      total = RedLoadBuffers(mgc,sym);
   }
   return(total);
}

bool RedOrderModifyBasket(int mgc, string sym, double SL, double TP, datetime exp, int maxTrades, color arrow=CLR_NONE)
{
   double   gapTP;
   double   stopLevel = MarketInfo( sym, MODE_STOPLEVEL ) * Point;
   int      total=GhostOrdersTotal();
//---- Assert optimize function by checking total > 0
   if( total<=0 ) return(false);

//--- Assert 8: Declare variables for OrderSelect #1
//       1-OrderModify BUY; 2-OrderClose BUY; 3-OrderModify SELL; 4-OrderClose SELL;
   int      aCommand[];
   int      aTicket[];
   double   aOpenPrice[];
   double   aStopLoss[];
   double   aTakeProfit[];
   datetime aExpiration[];
   bool     aOk;
   int      aCount;
//--- Assert 6: Dynamically resize arrays for OrderSelect #3
   ArrayResize(aCommand,maxTrades);
   ArrayResize(aTicket,maxTrades);
   ArrayResize(aOpenPrice,maxTrades);
   ArrayResize(aStopLoss,maxTrades);
   ArrayResize(aTakeProfit,maxTrades);
   ArrayResize(aExpiration,maxTrades);

//---- Assert determine count of all trades done with this MagicNumber
//       Init OrderSelect #1
   GhostInitSelect(true,0,SELECT_BY_POS,MODE_TRADES);
   for(int j=0;j<total;j++)
   {
      if ( !GhostOrderSelect(j,SELECT_BY_POS,MODE_TRADES) ) break;
   //--- Assert 6: Populate arrays for OrderSelect #3
      aCommand[aCount]     =  0;
      aTicket[aCount]      =  GhostOrderTicket();
      aOpenPrice[aCount]   =  GhostOrderOpenPrice();
      aStopLoss[aCount]    =  GhostOrderStopLoss();
      aTakeProfit[aCount]   =  GhostOrderTakeProfit();
      aExpiration[aCount]  =  GhostOrderExpiration();

   //---- Assert MagicNumber and Symbol is same as Order
      if (GhostOrderMagicNumber()==mgc && GhostOrderSymbol()==sym)
         if( GhostOrderType() == OP_BUY )
            gapTP = TP - Bid;
         if( GhostOrderType() == OP_SELL )
            gapTP = Ask - TP;
            
         if (( SL != 0 && SL != GhostOrderStopLoss() ) ||
             ( TP != 0 && TP != GhostOrderTakeProfit() ) ||
             ( exp != 0 && exp != GhostOrderExpiration() ))
         {
         //--- Assert 4: replace OrderModify a buy with arrays
            aCommand[aCount]     = 1;
            if( SL != 0 && SL != GhostOrderStopLoss() )                          aStopLoss[aCount]    = SL;
            if( TP != 0 && TP != GhostOrderTakeProfit() && gapTP > stopLevel )   aTakeProfit[aCount]  = TP;
            if( exp!= 0 && exp != GhostOrderExpiration() )                       aExpiration[aCount]  = exp;
            aCount ++;
            if( aCount >= maxTrades ) break;
         }
   }
//---- Assert 1: Free OrderSelect #1
   GhostFreeSelect(false);
//--- Assert for: process array of commands for OrderSelect #1
   aOk = true;
   for(int i=0; i<aCount; i++)
   {
      switch( aCommand[i] )
      {
         case 1:  // OrderModify Buy
            aOk = aOk && GhostOrderModify( aTicket[i], aOpenPrice[i], aStopLoss[i], aTakeProfit[i], aExpiration[i], arrow );
            break;
      }
   }   
   RedDebugPrint( 2,"RedOrderModifyBasket",
      RedDebugInt("mgc",mgc)+
      RedDebugStr("sym",sym)+
      RedDebugInt("total",total)+
      RedDebugInt("aCount",aCount)+
      RedDebugDbl("gapTP",gapTP,5)+
      RedDebugDbl("stopLevel",stopLevel,5)+
      RedDebugBln("aOk",aOk),
      false, 1 );
   return(aOk);
}

//|-----------------------------------------------------------------------------------------|
//|                             D E I N I T I A L I Z A T I O N                             |
//|-----------------------------------------------------------------------------------------|
void RedDeInit()
{
//-- Assert Excel or SQL files are saved.
}

//|-----------------------------------------------------------------------------------------|
//|                                     C O M M E N T                                       |
//|-----------------------------------------------------------------------------------------|
string RedComment(string cmt="", string basket1="Basket1", string basket2="Basket2")
{
   int i, total;
   
   string strtmp = cmt+"  -->"+RedName+" "+RedVer+"<--";

//--- Assert Mode info in comment
   strtmp=strtmp+"\n    BaseLot="+DoubleToStr(RedBaseLot,2)+"  BasketLevel="+DoubleToStr(RedBasketLevel,0);
   strtmp=strtmp+"\n    Mode="+DoubleToStr(RedMode,0);
   switch( RedMode )
   {
      case 0:
         strtmp=strtmp+" (Use 1x only)";
         break;
      case 1:
         strtmp=strtmp+" (Envy)";
         break;
      case 2:
         strtmp=strtmp+" (Fibo)";
         break;
   }
//--- Assert Cycle info in comment
   if( RedShortCycle )
      strtmp=strtmp+"  ShortCycle";
   else
      strtmp=strtmp+"  LongCycle";
   strtmp=strtmp+" (Pip="+DoubleToStr(redCyclePip,0)+")";
//--- Assert Basket info in comment
   int total1Magic = RedLoadBuffers( red1Magic, Symbol() );
   if( total1Magic >= RedBasketLevel )
      strtmp=strtmp+"\n    "+basket1+": Basket Level reached.";
   else
   {
      strtmp=strtmp+"\n    "+basket1+": Expected orders:";
      for(i=0; i<ArraySize(redPoTicket); i++)
      {
         strtmp=strtmp+"\n      "+DoubleToStr(i+total1Magic+1,0)+": lots="+DoubleToStr( redPoLots[i], 2 );
         if( total1Magic > 0 )
            strtmp=strtmp+" price="+DoubleToStr( redPoOpenPrice[i],5 );
      }
   }
   int total2Magic = RedLoadBuffers( red2Magic, Symbol() );
   if( total2Magic >= RedBasketLevel )
      strtmp=strtmp+"\n    "+basket2+": Basket Level reached.";
   else
   {
      strtmp=strtmp+"\n    "+basket2+": Expected orders:";
      for(i=0; i<ArraySize(redPoTicket); i++)
      {
         strtmp=strtmp+"\n      "+DoubleToStr(i+total2Magic+1,0)+": lots="+DoubleToStr( redPoLots[i], 2 );
         if( total2Magic > 0 )
            strtmp=strtmp+" price="+DoubleToStr( redPoOpenPrice[i],5 );
      }
   }
                         
   strtmp=strtmp+"\n";
   return(strtmp);
}

void RedDebugPrint(int dbg, string fn, string msg, bool incr=true, int mod=0)
{
   if(RedDebug>=dbg)
   {
      if(dbg>=2 && RedDebugCount>0)
      {
         if( MathMod(RedCount,RedDebugCount) == mod )
            Print(RedDebug,"-",RedCount,":",fn,"(): ",msg);
         if( incr )
            RedCount ++;
      }
      else
         Print(RedDebug,":",fn,"(): ",msg);
   }
}
string RedDebugInt(string key, int val)
{
   return( StringConcatenate(";",key,"=",val) );
}
string RedDebugDbl(string key, double val, int dgt=5)
{
   return( StringConcatenate(";",key,"=",NormalizeDouble(val,dgt)) );
}
string RedDebugStr(string key, string val)
{
   return( StringConcatenate(";",key,"=\"",val,"\"") );
}
string RedDebugBln(string key, bool val)
{
   string valType;
   if( val )   valType="true";
   else        valType="false";
   return( StringConcatenate(";",key,"=",valType) );
}

//|-----------------------------------------------------------------------------------------|
//|                           I N T E R N A L   F U N C T I O N S                           |
//|-----------------------------------------------------------------------------------------|
int RedCycleGap(int n, string sym, int period)
{
   double range, maxRange;
   for(int i=0; i<n; i++)
   {
      range = iHigh(sym,period,i) - iLow(sym,period,i);
      if( range > maxRange ) maxRange = range;
   }
   RedDebugPrint(0,"RedCycleGap",
      RedDebugInt("InitPts",InitPts) );
   return( MathRound( maxRange/InitPts ) );
}

//|-----------------------------------------------------------------------------------------|
//|                       E N D   O F   E X P E R T   A D V I S O R                         |
//|-----------------------------------------------------------------------------------------|