-- upgrade-3.2.6.0.0-3.2.7.0.0.sql


-- After upgrade V3.1.2 -> V3.2:
-- Make sure that there are no "intranet-timesheet" stuff left in the
-- title_tcl row of component plugins
update im_component_plugins set title_tcl = '_ ' || title_tcl where title_tcl like 'intranet-timesh%';
