//ejample of structure for simple test 
//this structure merge the generator with the driver 
//also it merge the Scoreboard with the checker and it doesn't have the assertion block as well


//          STRUCTURE 

 //env*
 //Scoreborad
 //Driver-Generator         Monitor 
 // Interface     
 //DUT 

 // switch 
 // inputs: Data and Direction 
 // if Direction is lower than parameter, then send the package to Dev A otherwise send it to Dev B

 module switch;

 #(
     parameter ADDR_WIDTH = 8 ;
     parameter DATA_WIDTH =16 ;
     parameter ADDR_DIV =8'h3f;
 )

 (
     input clk, 
     input rstn, 
     input vld,  // equals to push action 

     input [ADDR_WIDTH-1:0] addr, 
     input [DATA_WIDTH-1:0] data, 

     output reg [ADDR_WIDTH-1:0] addr_a,
     output reg [DATA_WIDTH-1:0] data_a, 

     output reg [ADDR_WIDTH-1:0] addr_b,
     output reg [DATA_WIDTH-1:0] data_b 

 );

 always @(posedge clk) begin

     if (!rstn) begin
         addr_a <=0;
         data_a <=0;
         addr_b <=0;
         data_b <0;
        end
    else begin
        if (vld)
            begin
                if (addr >= 0 & addr <= ADDR_DIV)begin
                    addr_a <= addr;
                    data_a <= data;
                    addr_b <=0;
                    data_b <=0;
                    end
                else begin 
                    addr_a <= 0;
                    data_a <= 0;
                    addr_b <=addr;
                    data_b <=data;
                    end 
            end
        end
    end
 endmodule 


/////////////////////////////////////////////////////////////////

            //TRANSACTION 

/////////////////////////////////////////////////////////////////
 //This is the base transaction objetc that will be used 
 // in the environment to initiate new transactions and 
 // capture transactions at DUT interface 

class switch_item;
    rand bit [7;0] addr;
    rand bit [15:0] data;
    bit [7:0] addr_a;
    bit [15:0] data_a;
    bit [7:0]  addr_b;
    bit [15:0] data_b;

        //This function allows us to print contesnts of the data 
        //packet so that is easier to track in a logfile 

    function void print (string tag="");
      $display("T=%0t %s addr=0x%0h data=0x%0h addr_a=ox%0h data_a=0x%0h addr_b=0x%0h data_b=0x%0h", $time, tag, addr, addr_a, data_a, addr_b, data_b);
    endfunction
endclass 


////////////////////////////////////////////////

////// INTERFACE 

////////////////////////////////////////////////

//design interface used to monitor activity and capture/drive 
//transactions 

interface switch_if (input bit clk);

logic rstn;
logic vld;
logic [7:0] addr;
logic [15:0] data;

logic [7:0] addr_a;
logic [15:0] data_a;

logic [7:0] addr_b;
logic [15:0] data_b;
endinterface 

///////////////////////////////////////////////////////

//          DRIVER/AGENT

/////////////////////////////////////////////////////

//The driver is responsible for driving transactions to the DUT
// all it does is to get a transaction from the mailbox if it is 
//avaiable and drive it out into the DUT interface

class driver;

virtual switch_if vif;
event drv_done;
mailbox drv_mbx;

    task run();
        $display("T= %0t [Driver] starting ... ", $time);
        @(posedge vif.clk); 

        //TRy to get a new transaction every time and the assign 
        // packet contents to the interface. But do this only if the 
        //design is ready to accept new transactions 

        forever begin
            switch_item item; 
            $display("T= %0t [Driver] waiting for item...", $time);
            drv_mbx.get(item);
            item.print("Driver");
            vif.vld <= 1;
            vif.addr <=item.addr;
            vif.data <= item.data;

            //When transfer is over, raise the done event
            @(posedge vif.clk);
            vif.vld <=0; ->drv_done;
            end
    endtask
endclass 

///////////////////////////////////////////////////

///////         GENERATOR

//////////////////////////////////////////////////

//The generator class is sued to generate a random 
//number of transactions with random adresses and data 
//that can be driven to the design 

class generator;
mailbox drv_mbx; // como se comunida con el driver 
event drv_done;
int num =20;

    task run();

        for (int i  =0 ; i<num ; i++) begin
            switch_item item = new;
            item.randomize();
            $display("T=%0t [Generator] Loop: %0d/%0d create next item", $time, i+1, num);
            drv_mbx.put(item);
            @ (drv_done);
        end
            $display("T=%0t [Generator] Done generation of %0d items",$time, num);
           
    endtask
endclass

////////////////////////////////////////////

////////            MONITOR 

////////////////////////////////////////////

//The monitor has a virtual interface handle with which 
// it can monitor the events happening on the interface.
// It sees new transactions and the captures information
// into a packet and sends it to the scoreboard
// using another mailbox 

class monitor;
    virtual switch_if vif;
    mailbox scb_mbx;
    semaphore sema4;

    function new();
        sema4= new (1);
    endfunction

    task run();
        $display("T=%0t [Monitor] starting ... ", $time);

        //to get a pipeline effect of transfers, fork two threads 
        // where each thread uses a semaphore for the address phase 
            
            fork
                sample_port("Thread0");
                sample_port("Thread1");
            join
    endtask 

    task sample_port (string tag ="");

    //this task monitors the interface for a complete 
    // transactions and pushes into the mailbox when the 
    // transaction is complete 

        forever begin
            @(posedge vif.clk);
            if (vif.rstn & vif.vld)begin 
                switch_item item =new;
                sema4.get();
                item.addr = vif.addr;
                item.data = vif.data;
                $display("T=%0t [Monitor] %s First part over", $time, tag);
                
                @(posedge vif.clk);
                sema4.put();
                item.addr_a = vif.addr_a;
                item.data_a = vif.data_a;
                item.addr_b = vif.addr_b;
                item.data_b = vif.data_b;
                $display("T=%0t [MOnitor] %s Second part over", $time, tag);

                scb_mbx.put(item);
                item.print({"Monitor_ ", tag});
            end 
        end 
    endtask 

endclass 

//////////////////////////////////////////////////////

/////               SCORE BOARD 

//////////////////////////////////////////////////////

//The scoreboard is responsible to check data integrity. since 
// the design routes packets based on an address range, the scoreborad 
//checks that the packet's address is within valid range 

class scoreboard;

    mailbox scb_mbx;

        task run ():
            forever begin 
                switch_item item;
                scb_mbx.get(item); 

                    if (item.addr inside {[0:'h3f]}) 
                        begin
                            if (item.addr_a != item.add | item.data_a != item.data)
                                $display("T=%0t [Scoreboard] ERROR! Mismatch addr=0x%0h data=0x%0h addr_a=0x%0h data_a=0x%0h", $time, item.addr, item.data, item.addr_a, item.data_a);
                                else 
                                $display("T=%0t [Scoreboard] PASS! Match addr=0x%0h data=0x%0h addr_a=0x%0h data_a=0x%0h", $time, item.addr, item.data, item.addr_a, item.data_a);
                        end
                    else 
                        begin 
                        
                        if (item.addr_b != item.addr | item.data_b != item.data)
                             
                             $display("T=%0t [Scoreboard] ERROR! Mismatch addr=0x%0h data=0x%0h addr_b=0x%0h data_b=0x%0h", $time, item.addr, item.data, item.addr_b, item.data_b);
                            else 
                            $display("T=%0t [Scoreboard] PASS! Match addr=0x%0h data=0x%0h addr_b=0x%0h data_b=0x%0h", $time, item.addr, item.data, item.addr_b, item.data_b);

                         end
            end  
        endtask
endclass 

////////////////////////////////////////

//              ENVIRONMENT 

///////////////////////////////////////


// The environment is container object simply to hold
//all verification components together. This environment can 
//then be reused later and all components in it would be
// automatically connected and available for use 

class env;

    driver  d0;             //Driver handle 
    monitor m0;             // Monitor handle 
    generator g0;           // Generator hadle 
    scoreboard s0;          // Scoreboard handle 

    mailbox drv_mbx;        //Connect GEN-> DRV
    mallbox scb_mbx;        //Connect MON-> SCB
    event drv_done;         //INdicates when driver is done 

    virtual switch_if vif;  //virtual interface hadle 

        function new();
            d0=new;
            m0=new:
            g0=new;
            s0=new;
            drv_mbx= new();
            scb_mbx= new();

            //conectando mailboxes

            d0.drv_mbx = drv_mbx;
            g0.drv_mbx = drv_mbx;
            m0.scb_mbx = scb_mbx;
            s0.scb_mbx = scb_mbx;

            //conectando los eventos 

            d0.drv_done=drv_done;
            g0.drv_done=drv_done;

        endfunction

    virtual task run ();
        d0.vif=vif;
        m0.vif=vif;
            fork
                d0.run();
                m0.run();
                g0.run();
                s0.run();
            join_any
    endtask

endclass 

/////////////////////////////////////

/// TEST    

////////////////////////////////////

class test;
    env 0;
    
    function new():
            e0=new;
    endfunction

    task run();
        e0.run();
    endtask 

endclass 

//////////////////////////////////////

// TOP TEST BENCH 

/////////////////////////////////////

//Top level testbench module to instantiate design, interface
// start clocks and run the test 

module tb; 
reg clk;

always #10 clk=~clk;

switch_if   _if (clk);

switch DUT (
    .clk(clk),
    .rstn(_if.rstn),
    .addr(_if.addr),
    .data(_if.data),
    .vld(_if. vld),
    .addr_a(_if.addr_a),
    .data_a(_if.data_a),
    .addr_b(_if.addr_b),
    .data_b(if.data_b)
);

test t0;

initial begin 
    {clk,_if.rstn} <=0;

    //apply reset and start stimulus 

    #20 _if.rstn <=1;
    t0=new;
    t0.e0.vif=_if;
    t0.run();

    //Because multiple components and clock are running 
    // in the background, we need to call $finish explicity 

    #50 $finish;
end 

//System task to dump VCD waveform file 

initial begin 
    $dumpvars;
    $dumpfile ("dump.vcd");
end 
endmodule