# Keep this migration in the affected root for upgrading existing state.
moved {
  from = aws_vpc.legacy
  to   = module.network.aws_vpc.this
}
