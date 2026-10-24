<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path=".">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.168116</TD_Version>
    <Name>top_cam_id</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P35MDG324</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="../rtl/top/top_cam_id.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
            <File Path="../rtl/camera/sccb_master.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
            <File Path="../rtl/camera/ov5640_id_reader.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="3"/>
                </FileInfo>
            </File>
        </Verilog>
        <ADC_FILE>
            <File Path="../constraints/top_cam_id.adc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="constraint_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
        </ADC_FILE>
        <SDC_FILE>
            <File Path="../constraints/top_cam_id.sdc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="constraint_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
        </SDC_FILE>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL>top_cam_id</LABEL>
        <MODULE>top_cam_id</MODULE>
        <CREATEINDEX>auto</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
